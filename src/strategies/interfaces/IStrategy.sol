// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title IStrategy
/// @notice Stateless range-selection and swap-ratio module for the vault.
///         All functions are called via staticcall; implementations MUST be stateless
///         or read-only. The vault re-validates outputs (lo < hi, within TickMath bounds).
interface IStrategy {
    /// @notice Compute the [tickLower, tickUpper] range for the next position,
    ///         centred on twapTick and aligned to tickSpacing.
    /// @param twapTick   TWAP tick from OracleLib (not spot — manipulation-resistant).
    /// @param tickSpacing Pool tick spacing.
    /// @return tickLower Lower bound of the new range (inclusive).
    /// @return tickUpper Upper bound of the new range (exclusive).
    function computeRange(
        int24 twapTick,
        int24 tickSpacing
    ) external view returns (int24 tickLower, int24 tickUpper);

    /// @notice Compute the optimal one-sided swap to maximise liquidity in [sqrtA, sqrtB].
    /// @param sqrtP  Current pool sqrtPriceX96.
    /// @param sqrtA  sqrtPriceX96 at tickLower.
    /// @param sqrtB  sqrtPriceX96 at tickUpper.
    /// @param bal0   Vault's idle token0 balance.
    /// @param bal1   Vault's idle token1 balance.
    /// @return zeroForOne True if token0 → token1 swap needed.
    /// @return amount     Amount of the input token to swap.
    function computeOptimalSwap(
        uint160 sqrtP,
        uint160 sqrtA,
        uint160 sqrtB,
        uint256 bal0,
        uint256 bal1
    ) external pure returns (bool zeroForOne, uint256 amount);
}
