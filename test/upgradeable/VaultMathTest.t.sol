// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {VaultMath} from "../../src/libraries/VaultMath.sol";

contract VaultMathTest is Test {
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
        uint160 sqrtP = 2_505_414_483_750_479_251_915_866_636;
        uint256 v = VaultMath.token1ToToken0(1e18, sqrtP);
        assertGt(v, 0);
    }
    function test_token1ToToken0_zeroPriceReverts() public {
        vm.expectRevert(VaultMath.InvalidPoolPrice.selector);
        VaultMath.token1ToToken0(1e18, 0);
    }
}
