// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/math/Math.sol";
import {LiquidityAmounts, TickMath} from "./UniswapV3Math.sol";

/// @title VaultMath
/// @notice Pure liquidity / slippage / tick math extracted verbatim from the monolith.
///         All price inputs are passed explicitly (TWAP sqrt price computed by the caller via
///         OracleLib) so this library never touches contract state or the pool.
library VaultMath {
    error InvalidPoolPrice();

    /// @dev Floor-divide tick by spacing, handling negative ticks correctly.
    function floor(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    /// @dev Ceiling-divide tick by spacing, handling negative ticks correctly.
    function ceil(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = floor(tick, spacing);
        return (floored == tick) ? tick : floored + spacing;
    }

    /// @dev token0 = token1 * 2^192 / sqrtP^2. Reverts on zero price.
    function token1ToToken0(uint256 amount1, uint160 sqrtPriceX96) internal pure returns (uint256) {
        if (sqrtPriceX96 == 0) revert InvalidPoolPrice();
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        return Math.mulDiv(amount1, uint256(1) << 192, Math.mulDiv(sqrtPrice, sqrtPrice, 1));
    }

    /// @dev token1 = token0 * sqrtP^2 / 2^192.
    function token0ToToken1(uint256 amount0, uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 temp = Math.mulDiv(amount0, sqrtPrice, uint256(1) << 96);
        return Math.mulDiv(temp, sqrtPrice, uint256(1) << 96);
    }

    /// @dev Optimal one-sided swap to maximise liquidity in [sqrtA, sqrtB].
    function computeOptimalSwap(
        uint160 sqrtP,
        uint160 sqrtA,
        uint160 sqrtB,
        uint256 balance0,
        uint256 balance1
    ) internal pure returns (bool swapZeroForOne, uint256 swapAmount) {
        if (sqrtP <= sqrtA) return (false, balance1);
        if (sqrtP >= sqrtB) return (true, balance0);

        uint128 l0 = LiquidityAmounts.getLiquidityForAmount0(sqrtP, sqrtB, balance0);
        uint128 l1 = LiquidityAmounts.getLiquidityForAmount1(sqrtA, sqrtP, balance1);

        if (l0 >= l1) {
            uint256 keep0 = LiquidityAmounts.getAmount0ForLiquidity(sqrtP, sqrtB, l1);
            return (true, balance0 > keep0 ? balance0 - keep0 : 0);
        } else {
            uint256 keep1 = LiquidityAmounts.getAmount1ForLiquidity(sqrtA, sqrtP, l0);
            return (false, balance1 > keep1 ? balance1 - keep1 : 0);
        }
    }

    /// @dev Slippage floor for a mint/remove, priced at the supplied TWAP sqrt price.
    function computeMintSlippage(
        uint160 sqrtTwap,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity,
        uint256 slippageBps
    ) internal pure returns (uint256 min0, uint256 min1) {
        uint160 sqrtLower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 exp0;
        uint256 exp1;

        if (liquidity > 0) {
            (exp0, exp1) = LiquidityAmounts.getAmountsForLiquidity(sqrtTwap, sqrtLower, sqrtUpper, liquidity);
        } else {
            uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(sqrtTwap, sqrtLower, sqrtUpper, amount0, amount1);
            (exp0, exp1) = LiquidityAmounts.getAmountsForLiquidity(sqrtTwap, sqrtLower, sqrtUpper, expectedLiq);
        }

        min0 = Math.mulDiv(exp0, 10_000 - slippageBps, 10_000, Math.Rounding.Floor);
        min1 = Math.mulDiv(exp1, 10_000 - slippageBps, 10_000, Math.Rounding.Floor);
    }

    /// @dev Min-out floor for a swap, priced at the supplied TWAP sqrt price.
    function computeSwapMinOut(
        uint256 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceX96,
        uint256 slippageBps
    ) internal pure returns (uint256 minOut) {
        uint256 expected = zeroForOne
            ? token0ToToken1(amountIn, sqrtPriceX96)
            : token1ToToken0(amountIn, sqrtPriceX96);
        minOut = Math.mulDiv(expected, 10_000 - slippageBps, 10_000, Math.Rounding.Floor);
    }
}
