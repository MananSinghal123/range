// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";
import {VaultFactory} from "../../src/factory/VaultFactory.sol";

contract BeaconProxyTest is BaseTest {
    RebalancerVaultUpgradeable internal impl;
    VaultFactory internal factory;

    // Second and third vaults sharing the same beacon (factory)
    RebalancerVaultUpgradeable internal vault2;
    RebalancerVaultUpgradeable internal vault3;

    MockCLPool internal pool2;
    MockCLPool internal pool3;
    Strategy internal strategy2;
    Strategy internal strategy3;

    function setUp() public override {
        super.setUp();

        impl = new RebalancerVaultUpgradeable();
        factory = new VaultFactory(
            address(impl),
            PM_ADDR,
            ROUTER_ADDR,
            address(adapter),
            guardian,
            owner
        );

        pool2 = new MockCLPool();
        pool2.initialize(address(0), address(token0), address(token1), TICK_SPACING, address(0), SQRT_PRICE_100K);
        pool2.setPrice(SQRT_PRICE_100K, TICK_100K);

        pool3 = new MockCLPool();
        pool3.initialize(address(0), address(token0), address(token1), TICK_SPACING, address(0), SQRT_PRICE_100K);
        pool3.setPrice(SQRT_PRICE_100K, TICK_100K);

        strategy2 = new Strategy(500);
        strategy3 = new Strategy(900);

        vm.startPrank(owner);
        vault2 = RebalancerVaultUpgradeable(payable(
            factory.deployVault(address(pool2), address(strategy2), owner, operator, owner, "Vault2", "V2")
        ));
        vault3 = RebalancerVaultUpgradeable(payable(
            factory.deployVault(address(pool3), address(strategy3), owner, operator, owner, "Vault3", "V3")
        ));
        vm.stopPrank();

        vm.startPrank(owner);
        token0.approve(address(vault2), type(uint256).max);
        token0.approve(address(vault3), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(alice);
        token0.approve(address(vault2), type(uint256).max);
        token0.approve(address(vault3), type(uint256).max);
        vm.stopPrank();
    }

    // ── Beacon state ─────────────────────────────────────────────────────────

    function test_beacon_initialImplementation() public view {
        assertEq(factory.implementation(), address(impl));
    }

    function test_beacon_ownerIsFactoryOwner() public view {
        assertEq(factory.owner(), owner);
    }

    // ── Registry ─────────────────────────────────────────────────────────────

    function test_registry_vaultCount() public view {
        assertEq(factory.vaultCount(), 2);
    }

    function test_registry_vaultForMapping() public view {
        assertEq(factory.vaultFor(address(pool2), address(strategy2)), address(vault2));
        assertEq(factory.vaultFor(address(pool3), address(strategy3)), address(vault3));
    }

    function test_registry_allVaultsOrdered() public view {
        assertEq(factory.allVaults(0), address(vault2));
        assertEq(factory.allVaults(1), address(vault3));
    }

    function test_registry_duplicateVaultReverts() public {
        vm.prank(owner);
        vm.expectRevert(VaultFactory.VaultExists.selector);
        factory.deployVault(address(pool2), address(strategy2), owner, operator, owner, "Dup", "D");
    }

    // ── Independent storage across proxies ───────────────────────────────────

    function test_storage_proxiesHaveIndependentNames() public view {
        assertEq(vault2.name(), "Vault2");
        assertEq(vault3.name(), "Vault3");
    }

    function test_storage_proxiesHaveIndependentStrategies() public view {
        assertEq(vault2.strategy(), address(strategy2));
        assertEq(vault3.strategy(), address(strategy3));
    }

    function test_storage_depositOnlyAffectsTargetVault() public {
        vm.prank(alice);
        vault2.deposit(1e6, alice);

        assertGt(vault2.totalAssets(), 0);
        assertEq(vault3.totalAssets(), 0);
    }

    function test_storage_sharesAreIndependent() public {
        vm.prank(alice);
        vault2.deposit(1e6, alice);

        assertGt(vault2.balanceOf(alice), 0);
        assertEq(vault3.balanceOf(alice), 0);
    }

    // ── Shared implementation via beacon ─────────────────────────────────────

    function test_sharedImpl_upgrade_affectsBothProxies() public {
        RebalancerVaultUpgradeable impl2 = new RebalancerVaultUpgradeable();

        vm.prank(owner);
        factory.upgradeTo(address(impl2));

        assertEq(factory.implementation(), address(impl2));
        // Both proxies now route through the new impl; storage is unaffected.
        assertEq(address(vault2.token0()), address(vault3.token0()));
    }

    function test_sharedImpl_onlyOwnerCanUpgrade() public {
        RebalancerVaultUpgradeable impl2 = new RebalancerVaultUpgradeable();

        vm.prank(alice);
        vm.expectRevert();
        factory.upgradeTo(address(impl2));

        vm.prank(owner);
        factory.upgradeTo(address(impl2));
        assertEq(factory.implementation(), address(impl2));
    }

    function test_sharedImpl_upgradePreservesVaultStorage() public {
        vm.prank(alice);
        vault2.deposit(1e6, alice);
        uint256 sharesBefore = vault2.balanceOf(alice);

        RebalancerVaultUpgradeable impl2 = new RebalancerVaultUpgradeable();
        vm.prank(owner);
        factory.upgradeTo(address(impl2));

        assertEq(vault2.balanceOf(alice), sharesBefore);
    }

    // ── Factory access control ────────────────────────────────────────────────

    function test_deployVault_onlyOwner() public {
        MockCLPool p = new MockCLPool();
        p.initialize(address(0), address(token0), address(token1), TICK_SPACING, address(0), SQRT_PRICE_100K);

        vm.prank(alice);
        vm.expectRevert();
        factory.deployVault(address(p), address(strategy2), owner, operator, owner, "X", "X");
    }

    function test_deployVault_zeroPoolReverts() public {
        vm.prank(owner);
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        factory.deployVault(address(0), address(strategy2), owner, operator, owner, "X", "X");
    }

    function test_deployVault_zeroStrategyReverts() public {
        vm.prank(owner);
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        factory.deployVault(address(pool2), address(0), owner, operator, owner, "X", "X");
    }

    // ── Guardian ─────────────────────────────────────────────────────────────

    function test_guardian_setGuardianOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.setGuardian(alice);

        vm.prank(owner);
        factory.setGuardian(alice);
        assertEq(factory.guardian(), alice);
    }

    function test_guardian_setGuardianZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        factory.setGuardian(address(0));
    }

    function test_guardian_pauseAllGuardianOnly() public {
        vm.prank(alice);
        vm.expectRevert(VaultFactory.NotGuardian.selector);
        factory.pauseAll();

        vm.prank(guardian);
        factory.pauseAll();

        assertTrue(vault2.paused());
        assertTrue(vault3.paused());
    }

    function test_guardian_pauseAllEmitsEvent() public {
        vm.prank(guardian);
        vm.expectEmit(false, false, false, true);
        emit VaultFactory.PausedAll(2);
        factory.pauseAll();
    }

    // ── Constructor guards ────────────────────────────────────────────────────

    function test_constructor_zeroPositionManagerReverts() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(address(impl), address(0), ROUTER_ADDR, address(adapter), guardian, owner);
    }

    function test_constructor_zeroSwapRouterReverts() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(address(impl), PM_ADDR, address(0), address(adapter), guardian, owner);
    }

    function test_constructor_zeroDexAdapterReverts() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(address(impl), PM_ADDR, ROUTER_ADDR, address(0), guardian, owner);
    }

    function test_constructor_zeroGuardianReverts() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        new VaultFactory(address(impl), PM_ADDR, ROUTER_ADDR, address(adapter), address(0), owner);
    }

    function test_constructor_immutablesSet() public view {
        assertEq(factory.positionManager(), PM_ADDR);
        assertEq(factory.swapRouter(), ROUTER_ADDR);
        assertEq(factory.dexAdapter(), address(adapter));
        assertEq(factory.guardian(), guardian);
    }
}
