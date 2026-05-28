// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IFactoryRegistry.sol";
import "./IVotingEscrow.sol";

/// @dev Minimal interface for compatibility with Slipstream contracts.
///      We can not import the original instance from Tigris contracts as it
///      contains custom errors which were introduced in Solidity 0.8.
interface IVoter {
    function factoryRegistry() external view returns (IFactoryRegistry);
    function gauges(address _pool) external view returns (address);
    function isAlive(address _gauge) external view returns (bool);
    function ve() external view returns (IVotingEscrow);
}
