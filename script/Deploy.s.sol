// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

/// @notice Legacy monolith deploy script — superseded by DeployBeaconAndFactory.s.sol
///         and DeployStrategyVaults.s.sol as part of the modular-upgradeable refactor.
///         Retained as a placeholder; the actual deployment scripts are in this directory.
contract Deploy is Script {
    function run() external pure {
        revert("Use DeployBeaconAndFactory.s.sol instead");
    }
}
