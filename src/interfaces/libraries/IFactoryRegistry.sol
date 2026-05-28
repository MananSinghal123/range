// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Minimal interface for compatibility with Slipstream contracts.
///      We can not import the original instance from Tigris contracts as it
///      contains custom errors which were introduced in Solidity 0.8.
interface IFactoryRegistry {
    function factoriesToPoolFactory(
        address poolFactory
    ) external returns (address votingRewardsFactory, address gaugeFactory);
}
