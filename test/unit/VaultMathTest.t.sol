// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {VaultMath} from "../../src/libraries/VaultMath.sol";
import {TickMath} from "../../src/libraries/UniswapV3Math.sol";

/// @dev External wrapper so the internal (inlined) library functions can be invoked across a
///      call boundary — required for `vm.expectRevert` and to exercise the complex internal math.
contract VaultMathHarness {
    function floor(int24 tick, int24 spacing) external pure returns (int24) {
        return VaultMath.floor(tick, spacing);
    }
    function ceil(int24 tick, int24 spacing) external pure returns (int24) {
        return VaultMath.ceil(tick, spacing);
    }
    function token1ToToken0(uint256 a, uint160 p) external pure returns (uint256) {
        return VaultMath.token1ToToken0(a, p);
    }
    function token0ToToken1(uint256 a, uint160 p) external pure returns (uint256) {
        return VaultMath.token0ToToken1(a, p);
    }
    function computeOptimalSwap(
        uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint256 b0, uint256 b1
    ) external pure returns (bool, uint256) {
        return VaultMath.computeOptimalSwap(sqrtP, sqrtA, sqrtB, b0, b1);
    }
    function computeMintSlippage(
        uint160 sqrtTwap, int24 lo, int24 hi, uint256 a0, uint256 a1, uint128 liq, uint256 bps
    ) external pure returns (uint256, uint256) {
        return VaultMath.computeMintSlippage(sqrtTwap, lo, hi, a0, a1, liq, bps);
    }
    function computeSwapMinOut(
        uint256 amountIn, bool zeroForOne, uint160 p, uint256 bps
    ) external pure returns (uint256) {
        return VaultMath.computeSwapMinOut(amountIn, zeroForOne, p, bps);
    }
}

contract VaultMathTest is Test {
    VaultMathHarness h;

    // Tick range straddling the price so both legs of liquidity math are non-trivial.
    uint160 constant SQRTP = 2_505_414_483_750_479_251_915_866_636; // ~tick 345_397
    int24 constant LO = 345_200;
    int24 constant HI = 345_600;

    function setUp() public {
        h = new VaultMathHarness();
    }

    function test_floor_positive() public pure {
        assertEq(VaultMath.floor(345_397, 200), 345_200);
    }
    function test_floor_negativeNonMultiple() public pure {
        assertEq(VaultMath.floor(-150, 200), -200);
    }
    function test_ceil_positiveNonMultiple() public pure {
        assertEq(VaultMath.ceil(345_397, 200), 345_400);
    }
    function test_ceil_exactMultipleUnchanged() public pure {
        assertEq(VaultMath.ceil(345_400, 200), 345_400);
    }

    function test_token1ToToken0_roundtripApprox() public pure {
        uint256 v = VaultMath.token1ToToken0(1e18, SQRTP);
        assertGt(v, 0);
    }
    function test_token1ToToken0_zeroPriceReverts() public {
        vm.expectRevert(VaultMath.InvalidPoolPrice.selector);
        h.token1ToToken0(1e18, 0);
    }
    function test_token0ToToken1_nonZero() public pure {
        assertGt(VaultMath.token0ToToken1(1e8, SQRTP), 0);
    }

    /// @dev computeOptimalSwap: when price is below the range, all token1 is swapped to token0.
    function test_computeOptimalSwap_belowRange_swapsToken1() public view {
        uint160 sqrtA = TickMath.getSqrtRatioAtTick(LO);
        uint160 sqrtB = TickMath.getSqrtRatioAtTick(HI);
        (bool z, uint256 amt) = h.computeOptimalSwap(sqrtA - 1, sqrtA, sqrtB, 5e7, 9e17);
        assertEq(z, false);
        assertEq(amt, 9e17);
    }

    /// @dev computeOptimalSwap: when price is above the range, all token0 is swapped to token1.
    function test_computeOptimalSwap_aboveRange_swapsToken0() public view {
        uint160 sqrtA = TickMath.getSqrtRatioAtTick(LO);
        uint160 sqrtB = TickMath.getSqrtRatioAtTick(HI);
        (bool z, uint256 amt) = h.computeOptimalSwap(sqrtB + 1, sqrtA, sqrtB, 5e7, 9e17);
        assertEq(z, true);
        assertEq(amt, 5e7);
    }

    /// @dev computeMintSlippage applies the (10000 - bps)/10000 floor to expected amounts.
    function test_computeMintSlippage_appliesFloor() public view {
        (uint256 min0Full, uint256 min1Full) =
            h.computeMintSlippage(SQRTP, LO, HI, 1e8, 1e18, 0, 0);  // 0 bps → exact expected
        (uint256 min0Cut, uint256 min1Cut) =
            h.computeMintSlippage(SQRTP, LO, HI, 1e8, 1e18, 0, 50); // 50 bps → reduced
        assertLe(min0Cut, min0Full);
        assertLe(min1Cut, min1Full);
    }

    /// @dev computeSwapMinOut floors the converted expected output by slippageBps.
    function test_computeSwapMinOut_floorsByBps() public view {
        uint256 full = h.computeSwapMinOut(1e18, false, SQRTP, 0);
        uint256 cut = h.computeSwapMinOut(1e18, false, SQRTP, 50);
        assertEq(full, VaultMath.token1ToToken0(1e18, SQRTP));
        assertLe(cut, full);
    }
}
