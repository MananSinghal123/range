// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RebalancerVault} from "../src/RebalancerVault.sol";
import {ICLPool} from "../src/interfaces/ICLPool.sol";

/// @notice One-time script to bootstrap the vault's first LP position.
///
/// Required env vars:
///   OWNER_PRIVATE_KEY  — private key of the vault owner (calls initializePosition)
///   VAULT_ADDRESS      — deployed RebalancerVault address
///
/// Optional env vars:
///   STRATEGY           — 0=TIGHT(±300), 1=MEDIUM(±700), 2=WIDE(±1200)  [default: 1]
///   TICK_LOWER         — override computed lower tick (skip auto-range if set)
///   TICK_UPPER         — override computed upper tick (skip auto-range if set)
///   AMOUNT0_PCT        — % of vault's idle token0 to deploy, 1–100        [default: 100]
///   AMOUNT1_PCT        — % of vault's idle token1 to deploy, 1–100        [default: 100]
///
/// Usage (dry-run):
///   forge script script/InitializePosition.s.sol \
///     --rpc-url $RPC_URL --account <keystore> \
///     -vvvv
///
/// Usage (broadcast):
///   forge script script/InitializePosition.s.sol \
///     --rpc-url $RPC_URL --account <keystore> \
///     --broadcast -vvvv
///
/// Or with a raw private key from env:
///   forge script script/InitializePosition.s.sol \
///     --rpc-url $RPC_URL --private-key $OWNER_PRIVATE_KEY \
///     --broadcast -vvvv

contract InitializePosition is Script {

    // ─── Tick math helpers (mirrors RebalancerVault._floor / _ceil) ──────────

    function _floor(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    function _ceil(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = _floor(tick, spacing);
        return (floored == tick) ? tick : floored + spacing;
    }

    // ─── Main ────────────────────────────────────────────────────────────────

    function run() external {
        // ── Env ───────────────────────────────────────────────────────────────
        uint256 ownerKey   = vm.envUint("OWNER_PRIVATE_KEY");
        address vaultAddr  = vm.envAddress("VAULT_ADDRESS");
        uint8   strategy   = uint8(vm.envOr("STRATEGY", uint256(1)));   // default MEDIUM
        uint256 amount0Pct = vm.envOr("AMOUNT0_PCT", uint256(100));
        uint256 amount1Pct = vm.envOr("AMOUNT1_PCT", uint256(100));

        require(amount0Pct >= 1 && amount0Pct <= 100, "AMOUNT0_PCT must be 1-100");
        require(amount1Pct >= 1 && amount1Pct <= 100, "AMOUNT1_PCT must be 1-100");
        require(strategy <= 2, "STRATEGY must be 0, 1, or 2");

        RebalancerVault vault = RebalancerVault(payable(vaultAddr));

        // ── Sanity checks ─────────────────────────────────────────────────────
        require(vault.tokenId() == 0,   "Position already initialized (tokenId != 0)");
        require(!vault.paused(),         "Vault is paused");

        // ── Pool state ────────────────────────────────────────────────────────
        ICLPool pool = vault.pool();
        (, int24 spotTick, , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();

        // ── Tick range ────────────────────────────────────────────────────────
        int24 tickLower;
        int24 tickUpper;

        // Allow manual override via env — useful when deployer wants a custom range
        bool hasOverride = (vm.envOr("TICK_LOWER", int256(type(int24).min)) != int256(type(int24).min));
        if (hasOverride) {
            tickLower = int24(int256(vm.envOr("TICK_LOWER", int256(0))));
            tickUpper = int24(int256(vm.envOr("TICK_UPPER", int256(0))));
            require(tickLower < tickUpper, "TICK_LOWER must be < TICK_UPPER");
        } else {
            int24 halfWidth = vault.strategyWidths(RebalancerVault.StrategyType(strategy));
            tickLower = _floor(spotTick - halfWidth, tickSpacing);
            tickUpper = _ceil(spotTick  + halfWidth, tickSpacing);
        }

        // Snap to tick spacing (no-op if already aligned, but defensive)
        require(tickLower % tickSpacing == 0, "tickLower not aligned to tick spacing");
        require(tickUpper % tickSpacing == 0, "tickUpper not aligned to tick spacing");
        require(tickLower < tickUpper, "Invalid range: tickLower >= tickUpper");

        // ── Token amounts ─────────────────────────────────────────────────────
        address token0Addr = address(vault.token0());
        address token1Addr = address(vault.token1());

        uint256 idle0 = IERC20(token0Addr).balanceOf(vaultAddr);
        uint256 idle1 = IERC20(token1Addr).balanceOf(vaultAddr);

        require(idle0 > 0 || idle1 > 0, "Vault has no tokens to deploy - deposit first");

        uint256 amount0Desired = (idle0 * amount0Pct) / 100;
        uint256 amount1Desired = (idle1 * amount1Pct) / 100;

        // On-chain slippage tolerance (mirrors vault's own _computeMintSlippage approach)
        uint256 slippageBps = vault.slippageBps();
        uint256 amount0Min  = (amount0Desired * (10_000 - slippageBps)) / 10_000;
        uint256 amount1Min  = (amount1Desired * (10_000 - slippageBps)) / 10_000;

        // ── Pre-flight summary ────────────────────────────────────────────────
        console.log("===========================================");
        console.log("InitializePosition - pre-flight check");
        console.log("===========================================");
        console.log("  vault          :", vaultAddr);
        console.log("  pool           :", address(pool));
        console.log("  token0         :", token0Addr);
        console.log("  token1         :", token1Addr);
        console.log("  spot tick      :", spotTick);
        console.log("  tick spacing   :", tickSpacing);
        console.log("  tickLower      :", tickLower);
        console.log("  tickUpper      :", tickUpper);
        console.log("  strategy       :", strategy == 0 ? "TIGHT" : strategy == 1 ? "MEDIUM" : "WIDE");
        console.log("  idle token0    :", idle0);
        console.log("  idle token1    :", idle1);
        console.log("  amount0Desired :", amount0Desired);
        console.log("  amount1Desired :", amount1Desired);
        console.log("  amount0Min     :", amount0Min);
        console.log("  amount1Min     :", amount1Min);
        console.log("  slippageBps    :", slippageBps);
        console.log("===========================================");

        // ── Broadcast ─────────────────────────────────────────────────────────
        vm.startBroadcast(ownerKey);

        vault.initializePosition(
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );

        vm.stopBroadcast();

        // ── Post-deploy summary ───────────────────────────────────────────────
        uint256 newTokenId = vault.tokenId();
        console.log("");
        console.log("===========================================");
        console.log("Position initialized successfully!");
        console.log("  tokenId        :", newTokenId);
        console.log("  rebalanceCount :", vault.rebalanceCount());
        console.log("===========================================");
        console.log("");
        console.log("The vault is now live. Next steps:");
        console.log("  1. Keeper bot will call rebalance() automatically when out-of-range");
        console.log("  2. Frontend Range / APY fields will populate on next page load");
        console.log("  3. Monitor: cast call $VAULT_ADDRESS 'isOutOfRange()(bool)' --rpc-url $RPC_URL");
    }
}
