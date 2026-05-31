// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UpgradeableBase.sol";

contract InitializeTest is UpgradeableBase {
    function test_initialState() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.operator(), operator);
        assertEq(address(vault.token0()), address(token0));
        assertEq(address(vault.token1()), address(token1));
        assertEq(vault.decimals(), 8);
        assertEq(vault.asset(), address(token0));
        assertEq(vault.performanceFeeBps(), 1000);
        assertEq(vault.feeRecipient(), owner);
        assertEq(vault.twapSeconds(), 300);
        assertEq(vault.maxTwapDeviationTicks(), int24(200));
        assertEq(vault.slippageBps(), 50);
        assertEq(vault.strategy(), address(strategy));
        assertEq(vault.dexAdapter(), address(adapter));
    }

    function test_cannotReinitialize() public {
        RebalancerVaultUpgradeable.InitParams memory p; // zeros
        vm.expectRevert();
        vault.initialize(p);
    }

    function test_implementationInitializersDisabled() public {
        RebalancerVaultUpgradeable impl = new RebalancerVaultUpgradeable();
        RebalancerVaultUpgradeable.InitParams memory p;
        vm.expectRevert();
        impl.initialize(p);
    }
}
