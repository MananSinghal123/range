// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

contract DepositWithdrawTest is BaseTest {
    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }

    function test_previewDeposit() public {
        assertEq(vault.previewDeposit(10e18), 10e18 - DEAD_SHARES);

        _initialDeposit(10e18);
        uint256 preview = vault.previewDeposit(5e18);
        vm.prank(bob);
        uint256 actual = vault.deposit(5e18, bob);
        assertApproxEqAbs(preview, actual, 1);
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_previewMint() public {
        assertEq(vault.previewMint(DEAD_SHARES + 1), 2 * DEAD_SHARES + 1);
        _initialDeposit(10e18);
        uint256 preview = vault.previewMint(3e18);
        vm.prank(bob);
        uint256 actual = vault.mint(3e18, bob);
        assertApproxEqAbs(preview, actual, 1);
        vm.prank(owner);
        vault.setPaused(true);
        assertEq(vault.maxMint(alice), 0);
    }

    function test_convertToShares_roundtrip() public {
        _initialDeposit(10e18);
        uint256 shares = vault.convertToShares(3e18);
        uint256 back = vault.convertToAssets(shares);
        assertApproxEqAbs(back, 3e18, 2);
    }

    function test_depositToken1_pausedReverts() public {
        vm.prank(owner);
        vault.setPaused(true);
        vm.prank(alice);
        vm.expectRevert();
        vault.depositToken1(1e8, alice);
    }

    function test_depositToken1_sameBlockWithdrawBlocked() public {
        vm.prank(alice);
        vault.depositToken1(2e8, alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(1e16, alice, alice);
    }

    function test_depositToken1_shareAccounting() public {
        // First deposit: dead shares minted, alice gets shares.
        uint256 sharesPrev = vault.previewDepositToken1(DEAD_SHARES + 1);
        console.log("Shares to mint for token1 deposit:", sharesPrev);
        vm.prank(alice);
        vault.depositToken1(DEAD_SHARES + 1, alice);
        assertEq(vault.balanceOf(address(0xdead)), DEAD_SHARES);
        assertGt(vault.balanceOf(alice), 1);

        // Second deposit: shares are proportional to token0-equivalent value.
        uint256 supplyBefore = vault.totalSupply();
        uint256 taBefore = vault.totalAssets();
        uint256 depositVal = vault.previewDepositToken1(1e8);

        vm.prank(bob);
        uint256 shares = vault.depositToken1(1e8, bob);

        assertGt(vault.totalSupply(), supplyBefore);
        assertApproxEqAbs(shares, (depositVal * supplyBefore) / taBefore, 2);
    }

    function test_withdraw_zeroAmountReverts() public {
        _initialDeposit(10e18);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(0, alice, alice);
    }

    function test_withdraw_zeroReceiverReverts() public {
        _initialDeposit(10e18);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(1e18, address(0), alice);
    }

    function test_withdraw_exceedsMaxReverts() public {
        _initialDeposit(10e18);
        uint256 max = vault.maxWithdraw(alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(max + 1, alice, alice);
    }

    function test_withdraw_pausedReverts() public {
        _initialDeposit(10e18);
        vm.prank(owner);
        vault.setPaused(true);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(1e18, alice, alice);
    }

    function test_withdraw_thirdPartyWithAllowance() public {
        _initialDeposit(10e18);
        uint256 withdrawAmt = 2e18;
        uint256 sharesToApprove = vault.previewWithdraw(withdrawAmt);

        vm.prank(alice);
        vault.approve(bob, sharesToApprove);

        uint256 balBefore = token0.balanceOf(carol);
        vm.prank(bob);
        vault.withdraw(withdrawAmt, carol, alice);

        assertApproxEqAbs(
            token0.balanceOf(carol) - balBefore,
            withdrawAmt,
            100
        );
        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_withdraw_thirdPartyWithoutAllowanceReverts() public {
        _initialDeposit(10e18);
        vm.prank(bob);
        vm.expectRevert();
        vault.withdraw(1e18, bob, alice);
    }

    function test_withdraw_withPosition_removesLiquidity() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);

        uint256 balBefore = token0.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(3e18, alice, alice);

        assertApproxEqAbs(token0.balanceOf(alice) - balBefore, 3e18, 1e6);
    }

    function test_redeem_zeroSharesReverts() public {
        _initialDeposit(10e18);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(0, alice, alice);
    }

    function test_redeem_zeroReceiverReverts() public {
        _initialDeposit(10e18);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(shares / 2, address(0), alice);
    }

    function test_redeem_exceedsMaxReverts() public {
        _initialDeposit(10e18);
        uint256 max = vault.maxRedeem(alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(max + 1, alice, alice);
    }

    function test_redeem_pausedReverts() public {
        _initialDeposit(10e18);
        vm.prank(owner);
        vault.setPaused(true);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(1, alice, alice);
    }

    function test_redeem_thirdPartyWithAllowance() public {
        _initialDeposit(10e18);
        uint256 shares = vault.balanceOf(alice) / 2;

        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        uint256 assets = vault.redeem(shares, carol, alice);

        assertGt(assets, 0);
        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_redeem_thirdPartyWithoutAllowanceReverts() public {
        _initialDeposit(10e18);
        vm.prank(bob);
        vm.expectRevert();
        vault.redeem(1, bob, alice);
    }

    function test_redeem_returnsCorrectAssets() public {
        _initialDeposit(10e18);
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertApproxEqAbs(assets, 10e18 - DEAD_SHARES, 100);
    }

    function test_redeem_fullRedemptionLeavesOnlyDeadShares() public {
        _initialDeposit(10e18);
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.redeem(shares, alice, alice);

        assertEq(vault.totalSupply(), DEAD_SHARES);
    }

    function test_redeem_withPosition_transfersToken0AndToken1() public {
        _initialDeposit(10e18);
        vm.prank(owner);
        token1.transfer(address(vault), 1e8);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(shares / 2, alice, alice);

        assertGt(token1.balanceOf(alice), 0);
    }
}
