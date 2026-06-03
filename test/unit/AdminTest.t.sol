// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

/// @notice Admin functions: setOperator, setPaused, setGuardian, oracle params,
///         ownership transfer, sweepToken success path.
contract AdminTest is BaseTest {
    function test_setOperator_updatesOperator() public {
        vm.prank(owner);
        vault.setOperator(bob);
        assertEq(vault.operator(), bob);
    }

    function test_setOperator_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setOperator(bob);
    }

    function test_setOperator_zeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setOperator(address(0));
    }

    function test_setOperator_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit OperatorUpdated(bob);
        vault.setOperator(bob);
    }

    // ── setPaused ─────────────────────────────────────────────────────────────

    function test_setPaused_ownerCanPause() public {
        vm.prank(owner);
        vault.setPaused(true);
        assertTrue(vault.paused());
    }

    function test_setPaused_ownerCanUnpause() public {
        vm.prank(owner);
        vault.setPaused(true);
        vm.prank(owner);
        vault.setPaused(false);
        assertFalse(vault.paused());
    }

    function test_setPaused_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setPaused(true);
    }

    // ── setGuardian ───────────────────────────────────────────────────────────

    function test_setGuardian_updatesGuardian() public {
        vm.prank(owner);
        vault.setGuardian(alice);
        assertEq(vault.guardian(), alice);
    }

    function test_setGuardian_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setGuardian(bob);
    }

    function test_setGuardian_zeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setGuardian(address(0));
    }

    // ── Oracle params ─────────────────────────────────────────────────────────

    function test_setTwapSeconds_updatesValue() public {
        vm.prank(owner);
        vault.setTwapSeconds(600);
        assertEq(vault.twapSeconds(), 600);
    }

    function test_setTwapSeconds_belowMinimumReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setTwapSeconds(59);
    }

    function test_setTwapSeconds_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setTwapSeconds(600);
    }

    function test_setMaxTwapDeviationTicks_updatesValue() public {
        vm.prank(owner);
        vault.setMaxTwapDeviationTicks(500);
        assertEq(vault.maxTwapDeviationTicks(), int24(500));
    }

    function test_setMaxTwapDeviationTicks_zeroReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setMaxTwapDeviationTicks(0);
    }

    function test_setMaxTwapDeviationTicks_over1000Reverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setMaxTwapDeviationTicks(1001);
    }

    function test_setSlippageBps_updatesValue() public {
        vm.prank(owner);
        vault.setSlippageBps(200);
        assertEq(vault.slippageBps(), 200);
    }

    function test_setSlippageBps_over500Reverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.setSlippageBps(501);
    }

    function test_setSlippageBps_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setSlippageBps(100);
    }

    // ── sweepToken success path ───────────────────────────────────────────────

    function test_sweepToken_transfersNonPoolToken() public {
        MockERC20 dust = new MockERC20("Dust", "DUST", 18);
        dust.mint(address(vault), 1e18);

        uint256 ownerBefore = dust.balanceOf(owner);
        vm.prank(owner);
        vault.sweepToken(address(dust), owner);

        assertEq(dust.balanceOf(owner), ownerBefore + 1e18);
        assertEq(dust.balanceOf(address(vault)), 0);
    }

    function test_sweepToken_zeroBalanceReverts() public {
        MockERC20 dust = new MockERC20("Dust", "DUST", 18);
        vm.prank(owner);
        vm.expectRevert();
        vault.sweepToken(address(dust), owner);
    }

    function test_sweepToken_zeroToReverts() public {
        MockERC20 dust = new MockERC20("Dust", "DUST", 18);
        dust.mint(address(vault), 1e18);
        vm.prank(owner);
        vm.expectRevert();
        vault.sweepToken(address(dust), address(0));
    }

    // ── Ownership transfer ────────────────────────────────────────────────────

    function test_transferOwnership_sameOwnerReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.transferOwnership(owner);
    }

    function test_acceptOwnership_wrongCallerReverts() public {
        vm.prank(owner);
        vault.transferOwnership(alice);
        vm.prank(bob);
        vm.expectRevert();
        vault.acceptOwnership();
    }

    function test_transferOwnership_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.transferOwnership(bob);
    }

    // ── Events ────────────────────────────────────────────────────────────────

    event OperatorUpdated(address indexed newOperator);
}
