// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {FixedWidthStrategy} from "../../src/strategies/FixedWidthStrategy.sol";
import {VaultMath} from "../../src/libraries/VaultMath.sol";

contract FixedWidthStrategyTest is Test {
    function test_computeRange_matchesMonolithFormula() public {
        FixedWidthStrategy s = new FixedWidthStrategy(300); // TIGHT
        int24 twap = 345_397;
        int24 spacing = 200;
        (int24 lo, int24 hi) = s.computeRange(twap, spacing);
        assertEq(lo, VaultMath.floor(twap - 300, spacing));
        assertEq(hi, VaultMath.ceil(twap + 300, spacing));
    }

    function test_halfWidthImmutable() public {
        assertEq(new FixedWidthStrategy(700).halfWidth(), int24(700));
        assertEq(new FixedWidthStrategy(1200).halfWidth(), int24(1200));
    }

    function test_constructorRejectsNonPositive() public {
        vm.expectRevert();
        new FixedWidthStrategy(0);
    }

    function test_computeOptimalSwap_matchesVaultMath() public {
        FixedWidthStrategy s = new FixedWidthStrategy(700);
        uint160 sqrtP = 2_505_414_483_750_479_251_915_866_636;
        uint160 sqrtA = 2_400_000_000_000_000_000_000_000_000;
        uint160 sqrtB = 2_600_000_000_000_000_000_000_000_000;
        (bool z, uint256 amt) = s.computeOptimalSwap(sqrtP, sqrtA, sqrtB, 1e8, 1e18);
        (bool z2, uint256 amt2) = VaultMath.computeOptimalSwap(sqrtP, sqrtA, sqrtB, 1e8, 1e18);
        assertEq(z, z2);
        assertEq(amt, amt2);
    }
}
