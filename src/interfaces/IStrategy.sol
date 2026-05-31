// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title IStrategy
/// @notice Range-selection module called by the vault via STATICCALL only (never delegatecall).
///         Stateless; the vault re-validates returned ticks before use.
interface IStrategy {
    /// @notice Compute the new position range, centred on `twapTick`, aligned to `tickSpacing`.
    function computeRange(int24 twapTick, int24 tickSpacing)
        external view returns (int24 tickLower, int24 tickUpper);

    /// @notice Off-chain helper mirroring the optimal one-sided swap math.
    function computeOptimalSwap(
        uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint256 bal0, uint256 bal1
    ) external pure returns (bool zeroForOne, uint256 amount);
}
