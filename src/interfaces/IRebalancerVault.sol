// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @notice Minimal interface used by VaultFactory to pause all deployed vaults.
interface IRebalancerVault {
    function pauseByGuardian() external;
}
