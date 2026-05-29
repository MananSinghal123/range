import { ethers } from "ethers";
import { provider, signer } from "./provider.js";
import {
  MAX_GAS_PRICE,
  MAX_GAS_GWEI,
  POLL_INTERVAL_MS,
  RebalancerVaultABI,
} from "./config.js";
import { vaultState, networkState } from "./state.js";
import { isNetworkError, isRetryableError, jitter } from "./errors.js";
import { logInfo, logWarn, logErr } from "./logger.js";

const Q96 = 2n ** 96n;
const Q192 = 2n ** 192n;

// Configurable slippage tolerance in basis points (default 0.5%)
const SLIPPAGE_BPS = BigInt(process.env.SLIPPAGE_BPS ?? "50");

// Minimal ABI for the three view calls needed to compute swap params
const VAULT_QUERY_ABI = [
  "function getPoolState() view returns (uint160 sqrtPriceX96, int24 tick)",
  "function getPosition() view returns (address, address, int24 tickSpacing, int24 tickLower, int24 tickUpper, uint128 liquidity)",
  "function strategyWidths(uint8) view returns (int24)",
];

function applySlippage(amount) {
  return (amount * (10000n - SLIPPAGE_BPS)) / 10000n;
}

// Approximate sqrt(1.0001^tick) in Q96 format using floating-point.
// Relative error ≈ 1e-9 — sufficient for swap sizing; exact bit-manipulation not needed here.
function sqrtRatioAtTick(tick) {
  const sqrtRatio = Math.exp(Math.log(1.0001) * tick * 0.5);
  const hi = Math.floor(sqrtRatio * 2 ** 48);
  return BigInt(hi) * 2n ** 48n;
}

// Mirrors the contract's _floor and _ceil helpers
function floorTick(tick, spacing) {
  return Math.floor(tick / spacing) * spacing;
}
function ceilTick(tick, spacing) {
  const floored = floorTick(tick, spacing);
  return floored === tick ? tick : floored + spacing;
}

// Mirror of LiquidityAmounts.getAmountsForLiquidity (Q96 fixed-point BigInt)
function getAmountsForLiquidity(sqrtP, sqrtA, sqrtB, liquidity) {
  if (liquidity === 0n) return { amount0: 0n, amount1: 0n };
  if (sqrtP < sqrtA) sqrtP = sqrtA;
  if (sqrtP > sqrtB) sqrtP = sqrtB;
  const amount0 = (liquidity * Q96 * (sqrtB - sqrtP)) / (sqrtP * sqrtB);
  const amount1 = (liquidity * (sqrtP - sqrtA)) / Q96;
  return { amount0, amount1 };
}

// Compute the optimal one-sided swap to maximise liquidity in [sqrtA, sqrtB] at price sqrtP.
//
// Derivation: each token provides independent liquidity L.
//   L0 = balance0 * sqrtP * sqrtB / (Q96 * (sqrtB - sqrtP))
//   L1 = balance1 * Q96 / (sqrtP - sqrtA)
// Maximise deployed liquidity by equalising L0 and L1.
// Cross-multiply to compare without division, then solve for the amount to swap.
function computeOptimalSwap(sqrtP, sqrtA, sqrtB, balance0, balance1) {
  // Price outside range — swap entire balance to the single required token
  if (sqrtP <= sqrtA) return { swapZeroForOne: false, swapAmount: balance1 };
  if (sqrtP >= sqrtB) return { swapZeroForOne: true, swapAmount: balance0 };

  const lhs = balance0 * sqrtP * sqrtB * (sqrtP - sqrtA); // proportional to L0
  const rhs = balance1 * Q96 * Q96 * (sqrtB - sqrtP); // proportional to L1

  if (lhs >= rhs) {
    // Excess token0 → swap token0 for token1
    const keep0 =
      (balance1 * Q96 * Q96 * (sqrtB - sqrtP)) /
      ((sqrtP - sqrtA) * sqrtP * sqrtB);
    return {
      swapZeroForOne: true,
      swapAmount: balance0 > keep0 ? balance0 - keep0 : 0n,
    };
  } else {
    // Excess token1 → swap token1 for token0
    const keep1 =
      (balance0 * sqrtP * sqrtB * (sqrtP - sqrtA)) /
      (Q96 * Q96 * (sqrtB - sqrtP));
    return {
      swapZeroForOne: false,
      swapAmount: balance1 > keep1 ? balance1 - keep1 : 0n,
    };
  }
}

// Build all eight rebalance() arguments from on-chain state.
async function computeRebalanceArgs(vaultAddr, strategy) {
  const query = new ethers.Contract(vaultAddr, VAULT_QUERY_ABI, provider);

  const [poolState, position, halfWidth] = await Promise.all([
    query.getPoolState(),
    query.getPosition(),
    query.strategyWidths(strategy),
  ]);

  const sqrtP = poolState.sqrtPriceX96;
  const currentTick = Number(poolState.tick);
  const tickSpacing = Number(position[2]); // _tickSpacing
  const tickLower = Number(position[3]); // _tickLower
  const tickUpper = Number(position[4]); // _tickUpper
  const liquidity = position[5]; // _liquidity

  // New range the contract will mint (mirrors _floor / _ceil in Solidity)
  const newTickLower = floorTick(currentTick - Number(halfWidth), tickSpacing);
  const newTickUpper = ceilTick(currentTick + Number(halfWidth), tickSpacing);

  // Estimate token amounts freed when removing the current position
  const currSqrtA = sqrtRatioAtTick(tickLower);
  const currSqrtB = sqrtRatioAtTick(tickUpper);
  const { amount0, amount1 } = getAmountsForLiquidity(
    sqrtP,
    currSqrtA,
    currSqrtB,
    liquidity,
  );

  const amount0MinRemove = applySlippage(amount0);
  const amount1MinRemove = applySlippage(amount1);

  // Optimal swap for the new range
  const newSqrtA = sqrtRatioAtTick(newTickLower);
  const newSqrtB = sqrtRatioAtTick(newTickUpper);
  const { swapZeroForOne, swapAmount } = computeOptimalSwap(
    sqrtP,
    newSqrtA,
    newSqrtB,
    amount0,
    amount1,
  );

  // Minimum swap output at current spot price minus slippage tolerance
  let swapAmountOutMin = 0n;
  if (swapAmount > 0n) {
    const expectedOut = swapZeroForOne
      ? (swapAmount * sqrtP * sqrtP) / Q192 // token0 → token1
      : (swapAmount * Q192) / (sqrtP * sqrtP); // token1 → token0
    swapAmountOutMin = applySlippage(expectedOut);
  }

  return [
    swapZeroForOne,
    swapAmount,
    swapAmountOutMin,
    amount0MinRemove,
    amount1MinRemove,
    0n,
    0n,
    strategy,
  ];
}

// ── Core functions ─────────────────────────────────────────────────────────────

export async function buildAndSendTx(contract, method, args, gasPrice, label) {
  const txRequest = await contract[method].populateTransaction(...args);
  const gasEstimate = await provider.estimateGas({
    ...txRequest,
    from: signer.address,
  });

  const response = await signer.sendTransaction({
    ...txRequest,
    nonce: await provider.getTransactionCount(signer.address, "pending"),
    gasLimit: (gasEstimate * 120n) / 100n,
    gasPrice,
  });

  logInfo(label, `${method} tx sent: ${response.hash}`);
  return response.wait();
}

export async function preflight() {
  const bal = await provider.getBalance(signer.address);
  logInfo(
    "preflight",
    `keeper=${signer.address} native balance=${ethers.formatEther(bal)}`,
  );
  if (bal === 0n)
    throw new Error("Keeper has zero native balance — top up before running");
}

export async function checkAndRebalance(watched) {
  const vs = vaultState[watched.vault];
  if (Date.now() < vs.nextAttemptAt) return;

  const vault = new ethers.Contract(
    watched.vault,
    RebalancerVaultABI,
    provider,
  );

  try {
    const tokenId = await vault.tokenId();
    if (tokenId === 0n) {
      logInfo(watched.label, "not initialized — skipping");
      return;
    }

    const isOutOfRange = await vault.isOutOfRange();
    logInfo(watched.label, `isOutOfRange=${isOutOfRange}`);
    if (!isOutOfRange) {
      vs.consecutiveFailures = 0;
      vs.nextAttemptAt = 0;
      return;
    }

    const isPaused = await vault.paused();
    if (isPaused) {
      logInfo(watched.label, "paused — rebalance skipped");
      vs.consecutiveFailures = 0;
      vs.nextAttemptAt = 0;
      return;
    }

    logInfo(
      watched.label,
      `OUT OF RANGE — triggering rebalance (strategy=${watched.strategy})`,
    );

    const feeData = await provider.getFeeData();
    const gasPrice = feeData.gasPrice ?? feeData.maxFeePerGas ?? MAX_GAS_PRICE;
    if (gasPrice > MAX_GAS_PRICE) {
      logWarn(
        watched.label,
        `gas too high (${ethers.formatUnits(gasPrice, "gwei")} gwei > ${MAX_GAS_GWEI}) — skipping`,
      );
      return;
    }

    const rebalanceArgs = await computeRebalanceArgs(
      watched.vault,
      watched.strategy,
    );
    logInfo(
      watched.label,
      `swap: zeroForOne=${rebalanceArgs[0]} amount=${rebalanceArgs[1]} outMin=${rebalanceArgs[2]}`,
    );

    const receipt = await buildAndSendTx(
      vault.connect(signer),
      "rebalance",
      rebalanceArgs,
      gasPrice,
      watched.label,
    );

    if (receipt?.status !== 1) throw new Error("rebalance tx reverted");

    vs.totalRebalances += 1;
    vs.lastRebalanceAt = Date.now();
    vs.consecutiveFailures = 0;
    vs.nextAttemptAt = 0;
    logInfo(
      watched.label,
      `rebalance #${vs.totalRebalances} confirmed in block ${receipt.blockNumber}`,
    );
  } catch (err) {
    vs.consecutiveFailures += 1;
    const baseBackoff =
      Number(POLL_INTERVAL_MS) * 2 ** Math.min(vs.consecutiveFailures, 6);
    vs.nextAttemptAt =
      Date.now() + jitter(Math.min(baseBackoff, 5 * 60 * 1000));
    if (isNetworkError(err)) networkState.failures += 1;
    logErr(watched.label, err instanceof Error ? err.message : String(err));
    if (!isRetryableError(err))
      logErr(watched.label, "non-retryable — manual attention may be required");
  }
}
