// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";

import {
    RebalancerVaultUpgradeable
} from "../src/RebalancerVaultUpgradeable.sol";
import {VaultFactory} from "../src/factory/VaultFactory.sol";
import {CLDexAdapter} from "../src/adapters/CLDexAdapter.sol";
import {Strategy} from "../src/strategies/Strategy.sol";
import {VaultLens} from "../src/VaultLens.sol";

contract DeployVault is Script {
    address constant MEZO_POOL = 0x026dB82AC7ABf60Bf1a81317c9DbD63702B85850;
    address constant MEZO_POS_MGR = 0x9B753e11bFEd0D88F6e1D2777E3c7dac42F96062;

    int24 constant HALF_WIDTH_TIGHT = 600; //  ±600  ticks  (~±0.6%)
    int24 constant HALF_WIDTH_MEDIUM = 2_000; //  ±2000 ticks  (~±2%)
    int24 constant HALF_WIDTH_WIDE = 6_000; //  ±6000 ticks  (~±6%)

    function run() external {
        // ── Load env ────────────────────────────────────────────────────────
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address guardian = vm.envOr("GUARDIAN_ADDRESS", owner);
        address feeRecipient = vm.envOr("FEE_RECIPIENT", owner);
        address pool = vm.envOr("POOL_ADDRESS", MEZO_POOL);
        address positionManager = vm.envOr("POSITION_MANAGER", MEZO_POS_MGR);
        address swapRouter = vm.envAddress("SWAP_ROUTER");

        vm.startBroadcast(deployerKey);


        RebalancerVaultUpgradeable impl = new RebalancerVaultUpgradeable();
        console2.log("Implementation:", address(impl));

        CLDexAdapter dexAdapter = new CLDexAdapter();
        console2.log("CLDexAdapter:  ", address(dexAdapter));

        VaultLens lens = new VaultLens();
        console2.log("VaultLens:     ", address(lens));

        VaultFactory factory = new VaultFactory(
            address(impl),
            positionManager,
            swapRouter,
            address(dexAdapter),
            guardian,
            owner
        );
        console2.log("VaultFactory:  ", address(factory));


        Strategy stratTight = new Strategy(HALF_WIDTH_TIGHT);
        Strategy stratMedium = new Strategy(HALF_WIDTH_MEDIUM);
        Strategy stratWide = new Strategy(HALF_WIDTH_WIDE);
        console2.log("Strategy tight: ", address(stratTight));
        console2.log("Strategy medium:", address(stratMedium));
        console2.log("Strategy wide:  ", address(stratWide));

        // ── 5. Deploy vaults ─────────────────────────────────────────────────
        // deploySeedAndInitialize requires factory owner == msg.sender.
        // The factory was constructed with `owner` as the UpgradeableBeacon
        // owner, but msg.sender is deployer. If owner != deployer, fall back
        // to deployVault (no seed).
        address deployer = vm.addr(deployerKey);
        bool deployerIsOwner = deployer == owner;

        uint256 seedAssets = vm.envOr("SEED_ASSETS", uint256(0));
        bool shouldSeed = deployerIsOwner && seedAssets > 0;

        address vaultTight = _deployVault(
            factory,
            pool,
            address(stratTight),
            owner,
            operator,
            feeRecipient,
            "Mezo MUSD/BTC Tight",
            "mMUSD-BTC-T",
            shouldSeed,
            seedAssets,
            "TIGHT"
        );
        address vaultMedium = _deployVault(
            factory,
            pool,
            address(stratMedium),
            owner,
            operator,
            feeRecipient,
            "Mezo MUSD/BTC Medium",
            "mMUSD-BTC-M",
            shouldSeed,
            seedAssets,
            "MEDIUM"
        );
        address vaultWide = _deployVault(
            factory,
            pool,
            address(stratWide),
            owner,
            operator,
            feeRecipient,
            "Mezo MUSD/BTC Wide",
            "mMUSD-BTC-W",
            shouldSeed,
            seedAssets,
            "WIDE"
        );

        vm.stopBroadcast();

        // ── Summary ──────────────────────────────────────────────────────────
        console2.log("\n=== Deployment Summary ===");
        console2.log("Implementation:  ", address(impl));
        console2.log("CLDexAdapter:    ", address(dexAdapter));
        console2.log("VaultLens:       ", address(lens));
        console2.log("VaultFactory:    ", address(factory));
        console2.log("Strategy tight:  ", address(stratTight));
        console2.log("Strategy medium: ", address(stratMedium));
        console2.log("Strategy wide:   ", address(stratWide));
        console2.log("Vault tight:     ", vaultTight);
        console2.log("Vault medium:    ", vaultMedium);
        console2.log("Vault wide:      ", vaultWide);
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    function _deployVault(
        VaultFactory factory,
        address pool,
        address strategy,
        address vaultOwner,
        address operator,
        address feeRecipient,
        string memory name,
        string memory symbol,
        bool shouldSeed,
        uint256 seedAssets,
        string memory envPrefix
    ) internal returns (address vault) {
        if (shouldSeed) {
            int24 tickLower = int24(
                int256(
                    vm.envOr(string.concat(envPrefix, "_TICK_LOWER"), int256(0))
                )
            );
            int24 tickUpper = int24(
                int256(
                    vm.envOr(string.concat(envPrefix, "_TICK_UPPER"), int256(0))
                )
            );

            vault = factory.deploySeedAndInitialize(
                pool,
                strategy,
                vaultOwner,
                operator,
                feeRecipient,
                name,
                symbol,
                seedAssets,
                tickLower,
                tickUpper,
                0, // amount0Min — accept any slippage on seed
                0 // amount1Min
            );
            console2.log(string.concat(name, " (seeded):"), vault);
        } else {
            vault = factory.deployVault(
                pool,
                strategy,
                vaultOwner,
                operator,
                feeRecipient,
                name,
                symbol
            );
            console2.log(string.concat(name, ":"), vault);
        }
    }
}
