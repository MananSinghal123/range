// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract DepositTest is UnitBase {
    // ─── totalAssets ──────────────────────────────────────────────────────────

    function test_totalAssets_emptyVault() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_totalAssets_afterDeposit_equalsDeposited() public {
        uint256 assets = 10e8;
        _initialDeposit(assets);
        assertEq(vault.totalAssets(), assets);
    }

    function test_totalAssets_includesIdleToken1() public {
        _initialDeposit(10e8);
        uint256 t1 = 1e18;
        vm.prank(owner);
        token1.transfer(address(vault), t1);
        assertGt(vault.totalAssets(), 10e8);
    }

    // ─── convertTo ────────────────────────────────────────────────────────────

    function test_convertToShares_afterDeposit_proportional() public {
        _initialDeposit(10e8);
        uint256 supply = vault.totalSupply();
        uint256 ta = vault.totalAssets();
        uint256 shares = vault.convertToShares(5e8);
        assertEq(shares, (5e8 * supply) / ta);
    }

    // ─── previewDeposit ───────────────────────────────────────────────────────

    function test_previewDeposit_firstDeposit_returnsAssetsMinusDead() public view {
        assertEq(vault.previewDeposit(10e8), 10e8 - DEAD_SHARES);
    }

    function test_previewDeposit_belowDead_returnsZero() public view {
        assertEq(vault.previewDeposit(DEAD_SHARES), 0);
    }

    function test_previewDeposit_subsequentDeposit_proportional() public {
        _initialDeposit(10e8);
        uint256 supply = vault.totalSupply();
        uint256 ta = vault.totalAssets();
        uint256 second = 5e8;
        assertEq(vault.previewDeposit(second), (second * supply) / ta);
    }

    // ─── previewMint ──────────────────────────────────────────────────────────

    function test_previewMint_emptyVault_returnsSharesPlusDead() public view {
        assertEq(vault.previewMint(10e8), 10e8 + DEAD_SHARES);
    }

    // ─── maxDeposit / maxMint ─────────────────────────────────────────────────

    function test_maxDeposit_paused() public {
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_maxMint_paused() public {
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxMint(alice), 0);
    }

    // ─── deposit ──────────────────────────────────────────────────────────────

    function test_deposit_firstDeposit_mintsDeadShares() public {
        vm.prank(alice);
        vault.deposit(10e8, alice);
        assertEq(vault.balanceOf(address(0xdead)), DEAD_SHARES);
    }

    function test_deposit_firstDeposit_sharesEqualsAssetsMinusDead() public {
        uint256 assets = 10e8;
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);
        assertEq(shares, assets - DEAD_SHARES);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_deposit_transfersToken0ToVault() public {
        uint256 assets = 10e8;
        uint256 aliceBefore = token0.balanceOf(alice);
        vm.prank(alice);
        vault.deposit(assets, alice);
        assertEq(token0.balanceOf(alice), aliceBefore - assets);
        assertEq(token0.balanceOf(address(vault)), assets);
    }

    function test_deposit_subsequentDeposit_proportionalShares() public {
        _initialDeposit(10e8);
        uint256 supplyBefore = vault.totalSupply();
        uint256 taBefore = vault.totalAssets();

        uint256 second = 5e8;
        vm.prank(bob);
        uint256 shares = vault.deposit(second, bob);

        assertEq(shares, (second * supplyBefore) / taBefore);
        assertEq(vault.balanceOf(bob), shares);
    }

    function test_deposit_minterCanDepositForAnotherReceiver() public {
        vm.prank(alice);
        vault.deposit(10e8, bob);
        assertGt(vault.balanceOf(bob), 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_deposit_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function test_deposit_revertsZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.deposit(10e8, address(0));
    }

    function test_deposit_revertsBelowMinDeposit() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.BelowMinDeposit.selector);
        vault.deposit(DEAD_SHARES, alice);
    }

    function test_deposit_revertsWhenPaused() public {
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("Vault: paused");
        vault.deposit(10e8, alice);
    }

    // ─── mint ─────────────────────────────────────────────────────────────────

    function test_mint_firstMint_chargesSharesPlusDead() public {
        uint256 shares = 10e8;
        uint256 aliceBefore = token0.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.mint(shares, alice);

        assertEq(assets, shares + DEAD_SHARES);
        assertEq(token0.balanceOf(alice), aliceBefore - assets);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.balanceOf(address(0xdead)), DEAD_SHARES);
    }

    function test_mint_subsequentMint_proportionalCost() public {
        _initialDeposit(10e8);
        uint256 targetShares = 5e8;
        uint256 expectedCost = vault.previewMint(targetShares);

        vm.prank(bob);
        uint256 actual = vault.mint(targetShares, bob);

        assertEq(actual, expectedCost);
        assertEq(vault.balanceOf(bob), targetShares);
    }

    function test_mint_revertsZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAmount.selector);
        vault.mint(0, alice);
    }

    function test_mint_revertsZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.mint(10e8, address(0));
    }

    function test_mint_revertsWhenPaused() public {
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("Vault: paused");
        vault.mint(10e8, alice);
    }

    // ─── Multi-user proportionality ───────────────────────────────────────────

    function test_multiUser_sharesProportionalToDeposit() public {
        vm.prank(alice);
        vault.deposit(10e8, alice);

        vm.prank(bob);
        vault.deposit(10e8, bob);

        // Alice's first deposit mints DEAD_SHARES to 0xdead, so alice gets assets-DEAD_SHARES.
        // Bob's second deposit uses proportional math and gets assets shares exactly.
        assertApproxEqAbs(vault.balanceOf(alice), vault.balanceOf(bob), DEAD_SHARES);
    }

    function test_multiUser_largerDepositGetsMoreShares() public {
        vm.prank(alice);
        vault.deposit(10e8, alice);

        vm.prank(bob);
        vault.deposit(20e8, bob);

        assertGt(vault.balanceOf(bob), vault.balanceOf(alice));
    }
}
