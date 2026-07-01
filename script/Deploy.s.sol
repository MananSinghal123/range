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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICLPool} from "../src/interfaces/pool/ICLPool.sol";
import {IStrategy} from "../src/strategies/interfaces/IStrategy.sol";

contract Deploy is Script {
    address constant MEZO_POOL = 0x026dB82AC7ABf60Bf1a81317c9DbD63702B85850;
    address constant MEZO_POS_MGR = 0x9B753e11bFEd0D88F6e1D2777E3c7dac42F96062;

    int24 constant HALF_WIDTH_TIGHT = 600; //  ±600  ticks  (~±0.6%)
    int24 constant HALF_WIDTH_MEDIUM = 2_000; //  ±2000 ticks  (~±2%)
    int24 constant HALF_WIDTH_WIDE = 6_000; //  ±6000 ticks  (~±6%)

    function run() external {
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

        address deployer = vm.addr(deployerKey);
        bool deployerIsOwner = deployer == owner;

        uint256 seedAssets = vm.envOr("SEED_ASSETS", uint256(0));
        bool shouldSeed = deployerIsOwner && seedAssets > 0;

        address vaultTight = _deployVault(
            factory,
            pool,
            address(stratTight),
            owner,
            deployer,
            operator,
            feeRecipient,
            "Mezo MUSD/BTC Tight",
            "mMUSD-BTC-T",
            shouldSeed,
            seedAssets
        );
        address vaultMedium = _deployVault(
            factory,
            pool,
            address(stratMedium),
            owner,
            deployer,
            operator,
            feeRecipient,
            "Mezo MUSD/BTC Medium",
            "mMUSD-BTC-M",
            shouldSeed,
            seedAssets
        );
        address vaultWide = _deployVault(
            factory,
            pool,
            address(stratWide),
            owner,
            deployer,
            operator,
            feeRecipient,
            "Mezo MUSD/BTC Wide",
            "mMUSD-BTC-W",
            shouldSeed,
            seedAssets
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
        address deployer,
        address operator,
        address feeRecipient,
        string memory name,
        string memory symbol,
        bool shouldSeed,
        uint256 seedAssets
    ) internal returns (address vault) {
        if (shouldSeed) {
            // Deploy with deployer as temporary owner so we can call admin fns.
            vault = factory.deployVault(
                pool,
                strategy,
                deployer,
                operator,
                feeRecipient,
                name,
                symbol
            );
            RebalancerVaultUpgradeable v = RebalancerVaultUpgradeable(
                payable(vault)
            );
            address token0 = address(v.token0());

            // Lower TWAP window for fresh testnet pools that lack 300s of history.
            v.setTwapSeconds(60);

            IERC20(token0).approve(vault, seedAssets);
            v.deposit(seedAssets, deployer);

            (, int24 currentTick, , , , ) = ICLPool(pool).slot0();
            int24 tickSpacing = ICLPool(pool).tickSpacing();
            (int24 tickLower, int24 tickUpper) = IStrategy(strategy)
                .computeRange(currentTick, tickSpacing);

            v.initializePosition(
                tickLower,
                tickUpper,
                IERC20(token0).balanceOf(vault),
                IERC20(address(v.token1())).balanceOf(vault),
                0,
                0
            );

            // Restore production TWAP window and transfer ownership to final owner.
            v.setTwapSeconds(300);
            v.transferOwnership(vaultOwner);

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
