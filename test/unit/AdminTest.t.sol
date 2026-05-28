// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract AdminTest is UnitBase {
    // ─── setOperator ──────────────────────────────────────────────────────────

    function test_setOperator_updatesOperator() public {
        address newOp = makeAddr("newOp");
        vm.prank(owner);
        vault.setOperator(newOp);
        assertEq(vault.operator(), newOp);
    }

    function test_setOperator_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.setOperator(alice);
    }

    function test_setOperator_revertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.setOperator(address(0));
    }

    // ─── setPaused ────────────────────────────────────────────────────────────

    function test_setPaused_pausesVault() public {
        vm.prank(owner);
        vault.setPaused(true);
        assertTrue(vault.paused());
    }

    function test_setPaused_unpausesVault() public {
        vm.prank(owner);
        vault.setPaused(true);
        vm.prank(owner);
        vault.setPaused(false);
        assertFalse(vault.paused());
    }

    function test_setPaused_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.setPaused(true);
    }

    // ─── transferOwnership ────────────────────────────────────────────────────

    function test_transferOwnership_setsPendingOwner() public {
        vm.prank(owner);
        vault.transferOwnership(alice);
        assertEq(vault.pendingOwner(), alice);
    }

    function test_transferOwnership_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.transferOwnership(bob);
    }

    function test_transferOwnership_revertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.transferOwnership(address(0));
    }

    function test_transferOwnership_revertsSameOwner() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.SameOwner.selector);
        vault.transferOwnership(owner);
    }

    // ─── acceptOwnership ──────────────────────────────────────────────────────

    function test_acceptOwnership_transfersOwnership() public {
        vm.prank(owner);
        vault.transferOwnership(alice);

        vm.prank(alice);
        vault.acceptOwnership();

        assertEq(vault.owner(), alice);
        assertEq(vault.pendingOwner(), address(0));
    }

    function test_acceptOwnership_revertsIfNotPendingOwner() public {
        vm.prank(owner);
        vault.transferOwnership(alice);

        vm.prank(bob);
        vm.expectRevert(RebalancerVault.NotPendingOwner.selector);
        vault.acceptOwnership();
    }

    // ─── proposePerformanceFee ────────────────────────────────────────────────

    function test_proposePerformanceFee_setsPending() public {
        vm.prank(owner);
        vault.proposePerformanceFee(500, feeRecip);

        assertEq(vault.pendingFeeBps(), 500);
        assertEq(vault.pendingFeeRecipient(), feeRecip);
    }

    function test_proposePerformanceFee_setsTimelock() public {
        vm.prank(owner);
        vault.proposePerformanceFee(500, feeRecip);

        assertEq(vault.feeChangeActiveAt(), block.timestamp + 2 days);
    }

    function test_proposePerformanceFee_revertsFeeTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.FeeTooHigh.selector);
        vault.proposePerformanceFee(1001, feeRecip);
    }

    function test_proposePerformanceFee_revertsZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.proposePerformanceFee(500, address(0));
    }

    function test_proposePerformanceFee_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.proposePerformanceFee(500, feeRecip);
    }

    // ─── applyPerformanceFee ──────────────────────────────────────────────────

    function test_applyPerformanceFee_appliesFee() public {
        _setFee(300);
        assertEq(vault.performanceFeeBps(), 300);
        assertEq(vault.feeRecipient(), feeRecip);
    }

    function test_applyPerformanceFee_revertsTimelockActive() public {
        vm.startPrank(owner);
        vault.proposePerformanceFee(500, feeRecip);

        vm.expectRevert(RebalancerVault.TimelockActive.selector);
        vault.applyPerformanceFee();
        vm.stopPrank();
    }

    function test_applyPerformanceFee_succeedsAtExactTimelock() public {
        vm.prank(owner);
        vault.proposePerformanceFee(500, feeRecip);

        vm.warp(block.timestamp + 2 days);
        vm.prank(owner);
        vault.applyPerformanceFee();

        assertEq(vault.performanceFeeBps(), 500);
    }

    function test_applyPerformanceFee_revertsIfNotOwner() public {
        vm.prank(owner);
        vault.proposePerformanceFee(500, feeRecip);
        _warpPastTimelock();

        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.applyPerformanceFee();
    }

    // ─── sweepToken ───────────────────────────────────────────────────────────

    function test_sweepToken_transfersBalance() public {
        MockERC20 rogue = new MockERC20("Rogue", "RGE", 18);
        rogue.mint(address(vault), 1000e18);

        uint256 ownerBefore = rogue.balanceOf(owner);
        vm.prank(owner);
        vault.sweepToken(address(rogue), owner);

        assertEq(rogue.balanceOf(owner), ownerBefore + 1000e18);
        assertEq(rogue.balanceOf(address(vault)), 0);
    }

    function test_sweepToken_revertsOnToken0() public {
        token0.mint(address(vault), 1);
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.InvalidToken.selector);
        vault.sweepToken(address(token0), owner);
    }

    function test_sweepToken_revertsOnToken1() public {
        token1.mint(address(vault), 1);
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.InvalidToken.selector);
        vault.sweepToken(address(token1), owner);
    }

    function test_sweepToken_revertsZeroTo() public {
        MockERC20 rogue = new MockERC20("Rogue", "RGE", 18);
        rogue.mint(address(vault), 1e18);

        vm.prank(owner);
        vm.expectRevert(RebalancerVault.ZeroAddress.selector);
        vault.sweepToken(address(rogue), address(0));
    }

    function test_sweepToken_revertsZeroBalance() public {
        MockERC20 rogue = new MockERC20("Rogue", "RGE", 18);
        vm.prank(owner);
        vm.expectRevert(RebalancerVault.ZeroAmount.selector);
        vault.sweepToken(address(rogue), owner);
    }

    function test_sweepToken_revertsIfNotOwner() public {
        MockERC20 rogue = new MockERC20("Rogue", "RGE", 18);
        rogue.mint(address(vault), 1e18);

        vm.prank(alice);
        vm.expectRevert(RebalancerVault.NotOwner.selector);
        vault.sweepToken(address(rogue), alice);
    }
}
