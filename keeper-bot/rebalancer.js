import { ethers } from "ethers";
import { provider, signer } from "./provider.js";
import {
  MAX_GAS_PRICE,
  MAX_GAS_GWEI,
  POLL_INTERVAL_MS,
  RebalancerVaultABI,
} from "./config.js";
import { vaultState, networkState } from "./state.js";
import { withNonce } from "./nonceManager.js";
import { isNetworkError, isRetryableError, jitter } from "./errors.js";
import { logInfo, logWarn, logErr } from "./logger.js";

const VAULT_LENS_ABI = [
  "function isOutOfRange(address vault) view returns (bool)",
  "function computeRebalanceParams(address vault) view returns (bool swapZeroForOne, uint256 swapAmount)",
];

async function computeRebalanceArgs(lensAddr, vaultAddr) {
  const lens = new ethers.Contract(lensAddr, VAULT_LENS_ABI, provider);
  const [swapZeroForOne, swapAmount] = await lens.computeRebalanceParams(vaultAddr);
  return [swapZeroForOne, swapAmount];
}

// ── Core functions ─────────────────────────────────────────────────────────────

export async function buildAndSendTx(contract, method, args, gasPrice, label) {
  const txRequest = await contract[method].populateTransaction(...args);
  const gasEstimate = await provider.estimateGas({
    ...txRequest,
    from: signer.address,
  });

  // Serialize nonce assignment + submission across all vaults (shared signer).
  const response = await withNonce((nonce) =>
    signer.sendTransaction({
      ...txRequest,
      nonce,
      gasLimit: (gasEstimate * 120n) / 100n,
      gasPrice,
    }),
  );

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

  if (!watched.lens) {
    logErr(watched.label, "LENS_ADDRESS not configured — set it in keeper-bot/.env");
    return;
  }

  const lens = new ethers.Contract(watched.lens, VAULT_LENS_ABI, provider);

  try {
    const tokenId = await vault.tokenId();
    if (tokenId === 0n) {
      logInfo(watched.label, "not initialized — skipping");
      return;
    }

    const isOutOfRange = await lens.isOutOfRange(watched.vault);
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
      watched.lens,
      watched.vault,
    );
    logInfo(
      watched.label,
      `swap: zeroForOne=${rebalanceArgs[0]} amount=${rebalanceArgs[1]}`,
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
