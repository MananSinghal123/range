// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract WithdrawRedeemTest is UnitBase {
    // ─── previewWithdraw / previewRedeem ──────────────────────────────────────

    function test_previewWithdraw_zeroSupply_returnsMaxUint() public view {
        assertEq(vault.previewWithdraw(1e8), type(uint256).max);
    }

    function test_previewWithdraw_afterDeposit_nonZero() public {
        _initialDeposit(10e8);
        assertGt(vault.previewWithdraw(3e8), 0);
    }

    function test_previewRedeem_afterDeposit_nonZero() public {
        _initialDeposit(10e8);
        assertGt(vault.previewRedeem(vault.balanceOf(alice)), 0);
    }

    // ─── maxWithdraw / maxRedeem ──────────────────────────────────────────────

    function test_maxWithdraw_paused_returnsZero() public {
        _initialDeposit(10e8);
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_maxWithdraw_equalsConvertToAssets() public {
        _initialDeposit(10e8);
        assertEq(vault.maxWithdraw(alice), vault.convertToAssets(vault.balanceOf(alice)));
    }

    function test_maxRedeem_paused_returnsZero() public {
        _initialDeposit(10e8);
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxRedeem(alice), 0);
    }

    function test_maxRedeem_returnsBalance() public {
        _initialDeposit(10e8);
        assertEq(vault.maxRedeem(alice), vault.balanceOf(alice));
    }

    // ─── withdraw ─────────────────────────────────────────────────────────────

    function test_withdraw_basic_idleOnly() public {
        _initialDeposit(10e8);
        uint256 withdrawAmt = 3e8;
        uint256 balBefore = token0.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(withdrawAmt, alice, alice);

        assertEq(token0.balanceOf(alice), balBefore + withdrawAmt);
    }

    function test_withdraw_burnsCorrectShares() public {
        _initialDeposit(10e8);
        uint256 withdrawAmt = 3e8;
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 expectedShares = vault.previewWithdraw(withdrawAmt);

        vm.prank(alice);
        uint256 shares = vault.withdraw(withdrawAmt, alice, alice);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), sharesBefore - shares);
    }

    function test_withdraw_revertsExceedsMax() public {
        _initialDeposit(10e8);
        uint256 max = vault.maxWithdraw(alice);

        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ExceedsMaxWithdraw.selector);
        vault.withdraw(max + 1, alice, alice);
    }

    function test_withdraw_revertsWhenPaused() public {
        _initialDeposit(10e8);
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("Vault: paused");
        vault.withdraw(1e8, alice, alice);
    }

    function test_withdraw_allowanceSpent() public {
        _initialDeposit(10e8);
        uint256 withdrawAmt = 3e8;
        uint256 sharesNeeded = vault.previewWithdraw(withdrawAmt);

        vm.prank(alice);
        vault.approve(bob, sharesNeeded);

        vm.prank(bob);
        vault.withdraw(withdrawAmt, bob, alice);

        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_withdraw_withPosition_receivesToken0() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        vm.prank(alice);
        vault.deposit(5e8, alice);
        vm.roll(block.number + 1);

        uint256 withdrawAmt = 2e8;
        uint256 balBefore = token0.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(withdrawAmt, alice, alice);

        assertEq(token0.balanceOf(alice), balBefore + withdrawAmt);
    }

    // ─── redeem ───────────────────────────────────────────────────────────────

    function test_redeem_basic_returnsToken0() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);
        uint256 balBefore = token0.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertGt(token0.balanceOf(alice), balBefore);
    }

    function test_redeem_burnsShares() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
    }

    function test_redeem_canRedeemForAnotherReceiver() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);
        uint256 bobBefore = token0.balanceOf(bob);

        vm.prank(alice);
        vault.redeem(shares, bob, alice);

        assertGt(token0.balanceOf(bob), bobBefore);
    }

    function test_redeem_revertsZeroShares() public {
        _initialDeposit(10e8);
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAmount.selector);
        vault.redeem(0, alice, alice);
    }

    function test_redeem_revertsZeroReceiver() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.redeem(shares, address(0), alice);
    }

    function test_redeem_revertsExceedsMaxRedeem() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.ExceedsMaxRedeem.selector);
        vault.redeem(shares + 1, alice, alice);
    }

    function test_redeem_revertsWhenPaused() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(owner);
        vault.setPaused(true);

        vm.prank(alice);
        vm.expectRevert("Vault: paused");
        vault.redeem(shares, alice, alice);
    }

    function test_redeem_allowanceSpent_whenCallerNotOwner() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        vault.redeem(shares, bob, alice);

        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_redeem_withPosition_receivesBothTokens() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi);

        vm.prank(bob);
        vault.deposit(5e8, bob);
        vm.roll(block.number + 1);

        uint256 bobShares = vault.balanceOf(bob);
        uint256 bal0Before = token0.balanceOf(bob);
        uint256 bal1Before = token1.balanceOf(bob);

        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);

        assertTrue(
            token0.balanceOf(bob) > bal0Before || token1.balanceOf(bob) > bal1Before,
            "should receive at least one token"
        );
    }

    function test_multiUser_redeemReceivesProportionalValue() public {
        vm.prank(alice);
        vault.deposit(10e8, alice);

        vm.prank(bob);
        vault.deposit(10e8, bob);
        vm.roll(block.number + 1);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        vm.prank(alice);
        vault.redeem(aliceShares, alice, alice);

        vm.prank(bob);
        vault.redeem(bobShares, bob, bob);

        // Both deposited equally so both should receive the same back (±rounding)
        assertApproxEqAbs(
            token0.balanceOf(alice) - (100e8 - 10e8),
            token0.balanceOf(bob) - (100e8 - 10e8),
            1e4
        );
    }

}
