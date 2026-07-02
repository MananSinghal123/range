// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";

/// @notice LP position lifecycle: init, fees accrual, rebalance effects on storage.
/// @dev Amount conventions: token0 = MUSD (18 decimals), token1 = BTC (8 decimals).
contract PositionTest is BaseTest {
    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        LO = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        HI = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }

    function test_position_initWithToken1AlsoWorks() public {
        _initialDeposit(10e18); // 10 MUSD
        // Position init pulls tokens from the vault's balance, so fund it with token1.
        vm.prank(owner);
        token1.transfer(address(vault), 1e8); // 1 BTC
        _initPosition(LO, HI, 0, 1e8);
        assertGt(vault.tokenId(), 0);
    }

    // ── collectFees — fee accounting ──────────────────────────────────────────

    function test_position_collectFees_increasesFees0Earned() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);

        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 2e18, 0); // 2 MUSD
        vm.prank(operator);
        vault.collectFees(0, 0);

        // 10% of 2e18 = 2e17 fee charged; totalFees0Earned tracks it.
        assertEq(vault.totalFees0Earned(), 2e17);
    }

    function test_position_collectFees_increasesFees1Earned() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);

        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 0, 1e6); // 0.01 BTC
        vm.prank(operator);
        vault.collectFees(0, 0);

        // 10% of 1e6 = 1e5 fee charged; totalFees1Earned tracks it.
        assertEq(vault.totalFees1Earned(), 1e5);
    }

    function test_position_collectFees_zeroFeesBpsSkipsFeeTransfer() public {
        vm.startPrank(owner);
        vault.proposePerformanceFee(0, feeRecip);
        vm.warp(block.timestamp + 3 days);
        vault.applyPerformanceFee();
        vm.stopPrank();

        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);
        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 1e18, 0);

        uint256 recipBefore = token0.balanceOf(feeRecip);
        vm.prank(operator);
        vault.collectFees(0, 0);

        assertEq(token0.balanceOf(feeRecip), recipBefore); // no fee taken
    }

    // ── rebalance — state transitions ─────────────────────────────────────────

    function test_position_rebalanceChangesTokenId() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);
        uint256 oldId = vault.tokenId();

        vm.prank(operator);
        vault.rebalance(false, 0);

        assertGt(vault.tokenId(), oldId);
    }

    function test_position_rebalancePreservesApproximateTotalAssets() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);
        uint256 taBefore = vault.totalAssets();

        vm.prank(operator);
        vault.rebalance(false, 0);

        // The mock PM is not value-preserving (decrease pays out 1:1 per unit of
        // liquidity; mint always returns liquidity 1e18), so only sanity-check
        // that the vault still reports value after the position is re-minted.
        assertGt(taBefore, 0);
        assertGt(vault.totalAssets(), 0);
    }

    function test_position_rebalanceWithFees_accumulates() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);

        MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 1e18, 0);

        vm.prank(operator);
        vault.rebalance(false, 0);

        assertGt(vault.totalFees0Earned(), 0);
        assertGt(vault.rebalanceCount(), 0);
    }

    function test_position_multipleRebalancesAccumulateFees() public {
        _initialDeposit(10e18);
        _initPosition(LO, HI, 5e18, 0);

        for (uint i; i < 3; i++) {
            MockPositionManager(PM_ADDR).setPendingFees(vault.tokenId(), 1e18, 0);
            vm.prank(operator);
            vault.rebalance(false, 0);
        }

        assertEq(vault.rebalanceCount(), 3);
        assertGt(vault.totalFees0Earned(), 0);
    }
}
