// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Strategy} from "../../src/strategies/Strategy.sol";
import {VaultMath} from "../../src/libraries/VaultMath.sol";

contract StrategyTest is Test {
    int24 constant TWAP = 345_397;
    int24 constant SPACING = 200;
    uint160 constant SQRTP = 2_505_414_483_750_479_251_915_866_636;

    function test_computeRange_matchesFloorCeilFormula() public {
        Strategy s = new Strategy(300);
        (int24 lo, int24 hi) = s.computeRange(TWAP, SPACING);
        assertEq(lo, VaultMath.floor(TWAP - 300, SPACING));
        assertEq(hi, VaultMath.ceil(TWAP + 300, SPACING));
    }

    function test_halfWidthIsImmutable() public {
        assertEq(new Strategy(700).halfWidth(), int24(700));
        assertEq(new Strategy(1200).halfWidth(), int24(1200));
    }

    function test_constructorRejectsZeroOrNegativeWidth() public {
        vm.expectRevert();
        new Strategy(0);
    }

    function test_computeRange_tightWidthNarrowerThanWide() public {
        Strategy tight = new Strategy(300);
        Strategy wide = new Strategy(1200);
        (int24 tLo, int24 tHi) = tight.computeRange(TWAP, SPACING);
        (int24 wLo, int24 wHi) = wide.computeRange(TWAP, SPACING);
        assertGt(tLo, wLo);
        assertLt(tHi, wHi);
    }

    function test_computeRange_negativeTwapHandledCorrectly() public {
        Strategy s = new Strategy(700);
        int24 negTwap = -1000;
        (int24 lo, int24 hi) = s.computeRange(negTwap, SPACING);
        assertLt(lo, hi);
        assertEq(lo, VaultMath.floor(negTwap - 700, SPACING));
        assertEq(hi, VaultMath.ceil(negTwap + 700, SPACING));
    }

}
