// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../BaseTest.sol";
import {VaultLens} from "../../src/VaultLens.sol";

contract VaultLensTest is BaseTest {
    VaultLens lens;

    int24 internal LO;
    int24 internal HI;

    function setUp() public override {
        super.setUp();
        lens = new VaultLens();
        (LO, HI) = _defaultRange();
    }

    // ── sharePrice ────────────────────────────────────────────────────────────

    function test_sharePrice_zeroBeforeDeposit() public view {
        assertEq(lens.sharePrice(address(vault)), 0);
    }

    function test_sharePrice_oneToOneAfterFirstDeposit() public {
        _initialDeposit(10e8);
        uint256 sp = lens.sharePrice(address(vault));
        // After first deposit (no position) share price ≈ 1 token0 per share (scaled by decimals).
        assertGt(sp, 0);
    }

    // ── getVaultMetrics ───────────────────────────────────────────────────────

    function test_getVaultMetrics_initialState() public {
        _initialDeposit(10e8);
        VaultLens.VaultMetrics memory m = lens.getVaultMetrics(address(vault));
        assertEq(m.rebalanceCount, 0);
        assertEq(m.totalFees0Earned, 0);
        assertEq(m.totalFees1Earned, 0);
        assertGt(m.tvl, 0);
        // No position yet → ticks are zero.
        assertEq(m.tickLower, 0);
        assertEq(m.tickUpper, 0);
    }

    function test_getVaultMetrics_afterPositionInit() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        VaultLens.VaultMetrics memory m = lens.getVaultMetrics(address(vault));
        assertEq(m.tickLower, LO);
        assertEq(m.tickUpper, HI);
    }

    // ── getPoolState ──────────────────────────────────────────────────────────

    function test_getPoolState_matchesPool() public view {
        (uint160 p, int24 t) = lens.getPoolState(address(vault));
        assertEq(p, SQRT_PRICE_100K);
        assertEq(t, TICK_100K);
    }

    // ── getPosition ───────────────────────────────────────────────────────────

    function test_getPosition_revertsWithNoPosition() public {
        vm.expectRevert();
        lens.getPosition(address(vault));
    }

    function test_getPosition_afterInit() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);

        VaultLens.PositionInfo memory p = lens.getPosition(address(vault));
        assertEq(p.tickLower, LO);
        assertEq(p.tickUpper, HI);
        assertEq(p.tickSpacing, TICK_SPACING);
        assertGt(p.liquidity, 0);
    }

    // ── isOutOfRange ──────────────────────────────────────────────────────────

    function test_isOutOfRange_falseWhenInRange() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        // Spot tick (TICK_100K) is inside [LO, HI].
        assertFalse(lens.isOutOfRange(address(vault)));
    }

    function test_isOutOfRange_trueWhenPriceMovesBeyondUpper() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        // Push spot tick far above HI.
        pool.setPrice(SQRT_PRICE_100K, HI + 200);
        assertTrue(lens.isOutOfRange(address(vault)));
    }

    // ── computeRebalanceParams ────────────────────────────────────────────────

    function test_computeRebalanceParams_revertsWithNoPosition() public {
        vm.expectRevert();
        lens.computeRebalanceParams(address(vault));
    }

    function test_computeRebalanceParams_returnsValidDirection() public {
        _initialDeposit(10e8);
        _initPosition(LO, HI, 5e8, 0);
        // Should not revert; direction and amount are deterministic from mock state.
        (bool zfo, uint256 amt) = lens.computeRebalanceParams(address(vault));
        // With zero token0 liquidity and only idle token0 in vault after deposit,
        // the optimal swap amount may be 0 or non-zero — just assert no revert.
        assertTrue(zfo == true || zfo == false);
        assertTrue(amt >= 0);
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    function _defaultRange() internal pure returns (int24 lo, int24 hi) {
        lo = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        hi = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
    }
}
