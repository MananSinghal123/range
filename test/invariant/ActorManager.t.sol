// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
// ActorHandler must be imported explicitly — BaseTest.sol does not re-export it.
import "./ActorHandler.t.sol";

contract ActorManager is CommonBase, StdCheats, StdUtils {
    ActorHandler[] public handlers;

    constructor(ActorHandler[] memory _handlers) {
        handlers = _handlers;
    }

    function deposit(uint256 handlerIndex, uint256 assets) external {
        handlers[bound(handlerIndex, 0, handlers.length - 1)].deposit(assets);
    }

    function redeem(uint256 handlerIndex, uint256 sharesPct) external {
        handlers[bound(handlerIndex, 0, handlers.length - 1)].redeem(sharesPct);
    }

    function depositToken1(uint256 handlerIndex, uint256 amount) external {
        handlers[bound(handlerIndex, 0, handlers.length - 1)].depositToken1(
            amount
        );
    }
}
