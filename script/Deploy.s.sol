// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RebalancerVault} from "../src/RebalancerVault.sol";
import {VaultLens} from "../src/VaultLens.sol";

contract Deploy is Script {
    function run() external {
        // ── Required env vars ──────────────────────────────────────────────────
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address pool = vm.envAddress("POOL_ADDRESS");
        string memory name = vm.envOr("VAULT_NAME", string("Mezo Rebalancer"));
        string memory sym = vm.envOr("VAULT_SYMBOL", string("mREBAL"));

        vm.startBroadcast(deployerKey);

        RebalancerVault vault = new RebalancerVault(
            owner,
            pool,
            operator,
            name,
            sym
        );

        VaultLens lens = new VaultLens();

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

        console.log("===========================================");
        console.log("VaultLens deployed");
        console.log("  address  :", address(lens));
        console.log("===========================================");
        console.log("");
    }
}
