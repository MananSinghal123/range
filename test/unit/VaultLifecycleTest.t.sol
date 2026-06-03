// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

/// @notice Core vault lifecycle: deposit → position → fees → rebalance → withdraw.
contract VaultLifecycleTest is BaseTest {
    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }

    // ── Deposit ───────────────────────────────────────────────────────────────

    function test_deposit_firstDepositMintsDeadShares() public {
        uint256 assets = 10e8;
        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertEq(vault.balanceOf(address(0xdead)), DEAD_SHARES);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(shares, assets - DEAD_SHARES);
    }

    function test_deposit_belowDeadSharesReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(DEAD_SHARES, alice);
    }

    function test_deposit_zeroAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(0, alice);
    }

    function test_deposit_secondDepositorGetsProportionalShares() public {
        _initialDeposit(10e8);

        uint256 supplyBefore = vault.totalSupply();
        uint256 taBefore = vault.totalAssets();

        vm.prank(bob);
        uint256 bobShares = vault.deposit(5e8, bob);

        assertApproxEqAbs(
            bobShares,
            (5e8 * supplyBefore) / taBefore,
            1
        );
    }

    function test_depositToken1_mintsSharesPricedViaTwap() public {
        _initialDeposit(10e8);
        uint256 sharesBefore = vault.totalSupply();

        vm.prank(alice);
        uint256 shares = vault.depositToken1(1e18, alice);
        assertGt(shares, 0);
        assertGt(vault.totalSupply(), sharesBefore);
    }

    // ── Same-block guard ──────────────────────────────────────────────────────

    function test_withdraw_sameBlockReverts() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10e8, alice);
        // Same block — no vm.roll() — must revert.
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(1e8, alice, alice);
    }

    // ── initializePosition ────────────────────────────────────────────────────

    function test_initializePosition_ownerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.initializePosition(LO, HI, 0, 0, 0, 0);
    }

    function test_initializePosition_setsTokenId() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        assertGt(vault.tokenId(), 0);
    }

    function test_initializePosition_cannotReinitialize() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        vm.startPrank(owner);
        vm.expectRevert();
        vault.initializePosition(LO, HI, 1e8, 0, 0, 0);
        vm.stopPrank();
    }

    function test_initializePosition_invalidRangeReverts() public {
        vm.startPrank(owner);
        vm.expectRevert();
        vault.initializePosition(HI, LO, 0, 0, 0, 0); // lo >= hi
        vm.stopPrank();
    }

    // ── collectFees ───────────────────────────────────────────────────────────

    function test_collectFees_operatorOnly() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        vm.prank(alice);
        vm.expectRevert();
        vault.collectFees(0, 0);
    }

    function test_collectFees_requiresPosition() public {
        vm.prank(operator);
        vm.expectRevert();
        vault.collectFees(0, 0);
    }

    function test_collectFees_deductsFeeToRecipient() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 1e6, 1e15);

        uint256 recipBefore0 = token0.balanceOf(owner); // feeRecipient == owner
        vm.prank(operator);
        vault.collectFees(0, 0);

        // 10% performance fee deducted.
        assertGt(token0.balanceOf(owner), recipBefore0);
    }

    // ── rebalance ─────────────────────────────────────────────────────────────

    function test_rebalance_mintsNewPosition() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        uint256 oldId = vault.tokenId();

        vm.prank(operator);
        vault.rebalance(false, 0);

        assertGt(vault.tokenId(), oldId);
        assertEq(vault.rebalanceCount(), 1);
    }

    function test_rebalance_incrementsRebalanceCount() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        vm.prank(operator);
        vault.rebalance(false, 0);
        vm.prank(operator);
        vault.rebalance(false, 0);

        assertEq(vault.rebalanceCount(), 2);
    }

    // ── withdraw / redeem ─────────────────────────────────────────────────────

    function test_withdraw_returnsToken0() public {
        uint256 assets = 10e8;
        _initialDeposit(assets);

        uint256 withdrawAmt = 2e8;
        uint256 balBefore = token0.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(withdrawAmt, alice, alice);

        assertApproxEqAbs(
            token0.balanceOf(alice) - balBefore,
            withdrawAmt,
            100
        );
    }

    function test_redeem_burnsSharesToTokens() public {
        _initialDeposit(10e8);
        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares / 2, alice, alice);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), shares - shares / 2);
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function test_transferOwnership_twoStep() public {
        vm.prank(owner);
        vault.transferOwnership(alice);
        assertEq(vault.pendingOwner(), alice);

        vm.prank(alice);
        vault.acceptOwnership();
        assertEq(vault.owner(), alice);
    }

    function test_proposeAndApplyPerformanceFee() public {
        vm.startPrank(owner);
        vault.proposePerformanceFee(500, feeRecip);
        vm.warp(block.timestamp + 3 days);
        vault.applyPerformanceFee();
        vm.stopPrank();

        assertEq(vault.performanceFeeBps(), 500);
        assertEq(vault.feeRecipient(), feeRecip);
    }

    function test_performanceFee_timelockEnforced() public {
        vm.startPrank(owner);
        vault.proposePerformanceFee(500, feeRecip);
        vm.expectRevert();
        vault.applyPerformanceFee(); // too early
        vm.stopPrank();
    }

    function test_sweepToken_revertsForPoolTokens() public {
        vm.prank(owner);
        vm.expectRevert();
        vault.sweepToken(address(token0), owner);
    }

    function test_pauseByGuardian() public {
        vm.prank(guardian);
        vault.pauseByGuardian();
        assertTrue(vault.paused());
    }

}
