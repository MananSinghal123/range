// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RebalancerVault} from "../src/RebalancerVault.sol";

contract Deploy is Script {
    function run() external {
        // ── Required env vars ──────────────────────────────────────────────────
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner       = vm.envAddress("OWNER_ADDRESS");
        address operator    = vm.envAddress("OPERATOR_ADDRESS");
        address pool        = vm.envAddress("POOL_ADDRESS");
        string  memory name = vm.envOr("VAULT_NAME",   string("Mezo Rebalancer"));
        string  memory sym  = vm.envOr("VAULT_SYMBOL", string("mREBAL"));

        // ── Optional: performance fee (max 10% = 1000 bps) ────────────────────
        // If set, proposes the fee — owner must call applyPerformanceFee()
        // after the 2-day timelock elapses.
        uint256 feeBps        = vm.envOr("PERFORMANCE_FEE_BPS",    uint256(0));
        address feeRecipient  = vm.envOr("FEE_RECIPIENT",          address(0));

        // ── Optional: TWAP / slippage overrides ───────────────────────────────
        uint32  twapSeconds   = uint32(vm.envOr("TWAP_SECONDS",    uint256(300)));
        int24   maxTwapTicks  = int24(int256(vm.envOr("MAX_TWAP_TICKS", uint256(200))));
        uint256 slippageBps   = vm.envOr("SLIPPAGE_BPS",           uint256(50));

        // ── Deploy ─────────────────────────────────────────────────────────────
        vm.startBroadcast(deployerKey);

        RebalancerVault vault = new RebalancerVault(
            owner,
            pool,
            operator,
            name,
            sym
        );

        // Apply any overrides that differ from contract defaults
        // (defaults: twapSeconds=300, maxTwapDeviation=200, slippage=50)
        if (twapSeconds != 300)  vault.setTwapSeconds(twapSeconds);
        if (maxTwapTicks != 200) vault.setMaxTwapDeviationTicks(maxTwapTicks);
        if (slippageBps != 50)   vault.setSlippageBps(slippageBps);

        // Propose performance fee if configured (requires applyPerformanceFee()
        // after 2-day timelock — see RebalancerVault.proposePerformanceFee)
        if (feeBps > 0 && feeRecipient != address(0)) {
            vault.proposePerformanceFee(feeBps, feeRecipient);
        }

        vm.stopBroadcast();

        // ── Summary ────────────────────────────────────────────────────────────
        console.log("===========================================");
        console.log("RebalancerVault deployed");
        console.log("  address  :", address(vault));
        console.log("  owner    :", owner);
        console.log("  operator :", operator);
        console.log("  pool     :", pool);
        console.log("  token0   :", address(vault.token0()));
        console.log("  token1   :", address(vault.token1()));
        console.log("  name     :", vault.name());
        console.log("  symbol   :", vault.symbol());
        if (feeBps > 0) {
            console.log("  fee (bps):", feeBps);
            console.log("  fee recip:", feeRecipient);
            console.log("  NOTE: call applyPerformanceFee() after 2-day timelock");
        }
        console.log("===========================================");
        console.log("");
        console.log("Next steps:");
        console.log("  1. Copy vault address into keeper-bot/.env  (VAULT_ADDRESS)");
        console.log("  2. Copy vault address into frontend/.env.local (NEXT_PUBLIC_VAULT_ADDRESS)");
        console.log("  3. Fund the keeper wallet with testnet BTC for gas");
        console.log("  4. Start keeper-bot: node keeper-bot/index.js");
        console.log("  5. Start frontend:   npm run dev  (inside frontend/)");
    }
}
