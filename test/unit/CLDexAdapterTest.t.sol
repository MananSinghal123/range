// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CLDexAdapter} from "../../src/adapters/CLDexAdapter.sol";
import {IDexAdapter} from "../../src/adapters/interfaces/IDexAdapter.sol";
import {MockCLPool} from "../mocks/MockCLPool.sol";

contract CLDexAdapterTest is Test {
    CLDexAdapter adapter;
    MockCLPool pool;
    int24 constant TICK = 345_397;
    uint160 constant SQRTP = 2_505_414_483_750_479_251_915_866_636;

    function setUp() public {
        vm.warp(10_000);
        adapter = new CLDexAdapter();
        pool = new MockCLPool();
        pool.initialize(address(0), address(1), address(2), 200, address(0), SQRTP);
        pool.setPrice(SQRTP, TICK);
    }

    function test_slot0_read() public view {
        (uint160 p, int24 t) = adapter.slot0(address(pool));
        assertEq(p, SQRTP);
        assertEq(t, TICK);
    }

    function test_tickSpacing_read() public view {
        assertEq(adapter.tickSpacing(address(pool)), int24(200));
    }

    function test_observe_read() public view {
        uint32[] memory ages = new uint32[](2);
        ages[0] = 300; ages[1] = 0;
        int56[] memory cum = adapter.observe(address(pool), ages);
        assertEq(cum.length, 2);
    }

}
