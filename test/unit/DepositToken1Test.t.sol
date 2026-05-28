// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract DepositToken1Test is UnitBase {
    // ─── previewDepositToken1 ─────────────────────────────────────────────────

    function test_previewDepositToken1_zeroAmount_returnsZero() public view {
        assertEq(vault.previewDepositToken1(0), 0);
    }

    function test_previewDepositToken1_returnsNonZero() public view {
        // 1000 MUSD at 100k MUSD/BTC → ~0.01 BTC = 1e6 satoshis
        uint256 shares = vault.previewDepositToken1(1000e18);
        assertGt(shares, 0);
    }

    function test_previewDepositToken1_subsequentDeposit_proportional() public {
        _initialDeposit(10e8);
        uint256 t1 = 1000e18;
        uint256 preview = vault.previewDepositToken1(t1);
        // Execute the actual deposit and compare
        vm.prank(bob);
        uint256 actual = vault.depositToken1(t1, bob);
        assertEq(actual, preview);
    }

    // ─── depositToken1 ────────────────────────────────────────────────────────

    function test_depositToken1_firstDeposit_mintsDeadShares() public {
        vm.prank(alice);
        vault.depositToken1(1000e18, alice);
        assertEq(vault.balanceOf(address(0xdead)), DEAD_SHARES);
    }

    function test_depositToken1_firstDeposit_mintsCorrectShares() public {
        uint256 t1 = 1000e18;
        vm.prank(alice);
        uint256 shares = vault.depositToken1(t1, alice);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_depositToken1_transfersToken1ToVault() public {
        uint256 t1 = 1000e18;
        uint256 aliceBefore = token1.balanceOf(alice);
        vm.prank(alice);
        vault.depositToken1(t1, alice);
        assertEq(token1.balanceOf(alice), aliceBefore - t1);
        assertEq(token1.balanceOf(address(vault)), t1);
    }

    function test_depositToken1_subsequentDeposit_proportionalShares() public {
        _initialDeposit(10e8);
        uint256 supplyBefore = vault.totalSupply();
        uint256 taBefore = vault.totalAssets();

        uint256 t1 = 1000e18;
        vm.prank(bob);
        uint256 shares = vault.depositToken1(t1, bob);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(bob), shares);
        // At 100k MUSD/BTC, 1000 MUSD = 0.01 BTC = 1e6 satoshis, well below the 10 BTC initial deposit.
        // Shares are proportional: shares = t0val * supplyBefore / taBefore << supplyBefore.
        assertLt(shares, supplyBefore);
        assertGt(taBefore, 0);
    }

    function test_depositToken1_canDepositForAnotherReceiver() public {
        vm.prank(alice);
        vault.depositToken1(1000e18, bob);
        assertGt(vault.balanceOf(bob), 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_depositToken1_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAmount.selector);
        vault.depositToken1(0, alice);
    }

    function test_depositToken1_revertsZeroReceiver() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.depositToken1(1e18, address(0));
    }

    function test_depositToken1_revertsWhenPaused() public {
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("Vault: paused");
        vault.depositToken1(1e18, alice);
    }

}
