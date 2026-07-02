// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {TickMath} from "../../src/libraries/UniswapV3Math.sol";
import {MockCLPool} from "../mocks/MockCLPool.sol";

contract OracleLibTest is Test {
    MockCLPool pool;
    int24 constant TICK = 345_397;
    uint160 constant SQRTP = 2_505_414_483_750_479_251_915_866_636;

    function setUp() public {
        vm.warp(10_000);
        pool = new MockCLPool();
        pool.initialize(address(0), address(1), address(2), 200, address(0), SQRTP);
        pool.setPrice(SQRTP, TICK);
    }

    function test_getTwapTick_matchesSpotWhenFlat() public view {
        // Mock observe() integrates _tick continuously, so TWAP == spot tick.
        assertEq(OracleLib.getTwapTick(address(pool), 300), TICK);
    }

    function test_isDepositAllowed_trueWhenFlatNotPaused() public view {
        assertTrue(OracleLib.isDepositAllowed(address(pool), 300, 200, false));
    }

    function test_isDepositAllowed_falseWhenPaused() public view {
        assertFalse(OracleLib.isDepositAllowed(address(pool), 300, 200, true));
    }

    function test_getTwapSqrtPrice_matchesTickMathAtTwapTick() public view {
        assertEq(
            OracleLib.getTwapSqrtPrice(address(pool), 300),
            TickMath.getSqrtRatioAtTick(TICK)
        );
    }
}
