// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./UpgradeableBase.sol";

contract AdapterPlumbingTest is UpgradeableBase {
    function test_getPoolState_readsThroughAdapter() public view {
        (uint160 p, int24 t) = vault.getPoolState();
        assertEq(p, SQRT_PRICE_100K);
        assertEq(t, TICK_100K);
    }

    function test_strategyBoundIsMedium() public view {
        assertEq(vault.strategy(), address(strategy));
    }
}
