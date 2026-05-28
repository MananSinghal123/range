// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UnitBase.sol";

contract ViewTest is UnitBase {
    // ─── getPoolState ─────────────────────────────────────────────────────────

    function test_getPoolState_returnsConfiguredPrice() public view {
        (uint160 sqrtPrice, int24 tick) = vault.getPoolState();
        assertEq(sqrtPrice, SQRT_PRICE_100K);
        assertEq(tick, TICK_100K);
    }

    function test_getPoolState_reflectsPriceChange() public {
        uint160 newPrice = SQRT_PRICE_100K / 2;
        int24 newTick = TICK_100K - 6931;
        pool.setPrice(newPrice, newTick);

        (uint160 p, int24 t) = vault.getPoolState();
        assertEq(p, newPrice);
        assertEq(t, newTick);
    }

    // ─── getPosition ──────────────────────────────────────────────────────────

    function test_getPosition_revertsNotInitialized() public {
        vm.expectRevert(RebalancerVault.NotInitialized.selector);
        vault.getPosition();
    }

    function test_getPosition_returnsCorrectTokens() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        (address t0, address t1, , , , ) = vault.getPosition();
        assertEq(t0, address(token0));
        assertEq(t1, address(token1));
    }

    function test_getPosition_returnsCorrectRange() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        (, , , int24 tlo, int24 thi, ) = vault.getPosition();
        assertEq(tlo, lo);
        assertEq(thi, hi);
    }

    function test_getPosition_returnsNonZeroLiquidity() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        (, , , , , uint128 liq) = vault.getPosition();
        assertGt(liq, 0);
    }

    // ─── isOutOfRange ─────────────────────────────────────────────────────────

    function test_isOutOfRange_revertsNotInitialized() public {
        vm.expectRevert(RebalancerVault.NotInitialized.selector);
        vault.isOutOfRange();
    }

    function test_isOutOfRange_falseWhenTickInRange() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        assertFalse(vault.isOutOfRange());
    }

    function test_isOutOfRange_trueWhenTickBelowRange() public {
        _initialDeposit(INITIAL_DEPOSIT);
        // Range entirely above current tick
        int24 lo = ((TICK_100K + 2000) / TICK_SPACING) * TICK_SPACING;
        int24 hi = lo + TICK_SPACING * 10;
        _initPosition(lo, hi, 5e7, 0);

        assertTrue(vault.isOutOfRange());
    }

    function test_isOutOfRange_trueWhenTickAtOrAboveUpper() public {
        _initialDeposit(INITIAL_DEPOSIT);
        // Range entirely below current tick
        int24 hi = ((TICK_100K - 2000) / TICK_SPACING) * TICK_SPACING;
        int24 lo = hi - TICK_SPACING * 10;
        _initPosition(lo, hi, 5e7, 0);

        assertTrue(vault.isOutOfRange());
    }

    function test_isOutOfRange_reflectsPriceMovement() public {
        _initialDeposit(INITIAL_DEPOSIT);
        (int24 lo, int24 hi) = _defaultRange();
        _initPosition(lo, hi, 5e7, 0);

        assertFalse(vault.isOutOfRange());

        // Move price far out of range
        pool.setPrice(SQRT_PRICE_100K / 100, TICK_100K - 50000);

        assertTrue(vault.isOutOfRange());
    }

    // ─── sharePrice ───────────────────────────────────────────────────────────

    function test_sharePrice_zeroWhenNoSupply() public view {
        assertEq(vault.sharePrice(), 0);
    }

    function test_sharePrice_nonZeroAfterDeposit() public {
        _initialDeposit(INITIAL_DEPOSIT);
        assertGt(vault.sharePrice(), 0);
    }

    function test_sharePrice_scaledToDecimals0() public {
        _initialDeposit(10e8);
        // totalAssets = 10e8, totalSupply = 10e8 (first deposit)
        // sharePrice = totalAssets * 1e8 / totalSupply = 1e8
        assertEq(vault.sharePrice(), 1e8);
    }

    function test_sharePrice_stableAfterPositionInit() public {
        _initialDeposit(INITIAL_DEPOSIT);
        uint256 priceBefore = vault.sharePrice();

        (int24 lo, int24 hi) = _defaultRange();
        _initSmallPosition(lo, hi); // small liquidity avoids overflow in getAmountsForLiquidity

        uint256 priceAfter = vault.sharePrice();
        assertApproxEqRel(priceAfter, priceBefore, 0.01e18); // 1% tolerance
    }

    function test_sharePrice_unchangedAfterSecondDeposit() public {
        _initialDeposit(INITIAL_DEPOSIT);
        uint256 priceBefore = vault.sharePrice();

        vm.prank(bob);
        vault.deposit(5e8, bob);

        uint256 priceAfter = vault.sharePrice();
        assertApproxEqRel(priceAfter, priceBefore, 0.01e18);
    }

    // ─── onERC721Received ─────────────────────────────────────────────────────

    function test_onERC721Received_returnsSelector() public view {
        bytes4 sel = vault.onERC721Received(address(0), address(0), 0, "");
        assertEq(sel, vault.onERC721Received.selector);
    }

}
