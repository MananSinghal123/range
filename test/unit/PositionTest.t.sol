// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

/// @notice LP position lifecycle: init, fees accrual, rebalance effects on storage.
contract PositionTest is BaseTest {
    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }



    function test_position_initWithToken1AlsoWorks() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 0, 1e18);
        assertGt(vault.tokenId(), 0);
    }

    // ── collectFees — fee accounting ──────────────────────────────────────────

    function test_position_collectFees_increasesFees0Earned() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 2e6, 0);
        vm.prank(operator);
        vault.collectFees(0, 0);

        // 10% of 2e6 = 2e5 fee charged; totalFees0Earned tracks it.
        assertGt(vault.totalFees0Earned(), 0);
    }

    function test_position_collectFees_increasesFees1Earned() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 0, 5e15);
        vm.prank(operator);
        vault.collectFees(0, 0);

        assertGt(vault.totalFees1Earned(), 0);
    }

    function test_position_collectFees_zeroFeesBpsSkipsFeeTransfer() public {
        vm.startPrank(owner);
        vault.proposePerformanceFee(0, feeRecip);
        vm.warp(block.timestamp + 3 days);
        vault.applyPerformanceFee();
        vm.stopPrank();

        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 1e6, 0);

        uint256 recipBefore = token0.balanceOf(feeRecip);
        vm.prank(operator);
        vault.collectFees(0, 0);

        assertEq(token0.balanceOf(feeRecip), recipBefore); // no fee taken
    }

    // ── rebalance — state transitions ─────────────────────────────────────────

    function test_position_rebalanceChangesTokenId() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        uint256 oldId = vault.tokenId();

        vm.prank(operator);
        vault.rebalance(false, 0);

        assertGt(vault.tokenId(), oldId);
    }

    function test_position_rebalancePreservesApproximateTotalAssets() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        uint256 taBefore = vault.totalAssets();

        vm.prank(operator);
        vault.rebalance(false, 0);

        // Total assets should not meaningfully change (no slippage in mocks).
        assertApproxEqAbs(vault.totalAssets(), taBefore, 1e6);
    }

    function test_position_rebalanceWithFees_accumulates() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 1e6, 0);

        vm.prank(operator);
        vault.rebalance(false, 0);

        assertGt(vault.totalFees0Earned(), 0);
        assertGt(vault.rebalanceCount(), 0);
    }

    function test_position_multipleRebalancesAccumulateFees() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        for (uint i; i < 3; i++) {
            MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 1e6, 0);
            vm.prank(operator);
            vault.rebalance(false, 0);
        }

        assertEq(vault.rebalanceCount(), 3);
        assertGt(vault.totalFees0Earned(), 0);
    }
}
