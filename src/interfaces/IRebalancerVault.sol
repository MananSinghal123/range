// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title IRebalancerVault
/// @notice External surface of RebalancerVaultUpgradeable used by the factory and integrators.
interface IRebalancerVault {
    function initializePosition(
        int24 tickLower, int24 tickUpper,
        uint256 amount0Desired, uint256 amount1Desired,
        uint256 amount0Min, uint256 amount1Min
    ) external;
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function setPaused(bool paused) external;
    function pauseByGuardian() external;
    function owner() external view returns (address);
    function operator() external view returns (address);
    function tokenId() external view returns (uint256);
}
