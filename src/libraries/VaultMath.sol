// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library VaultMath {
    error InvalidPoolPrice();

    function floor(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    function ceil(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 floored = floor(tick, spacing);
        return (floored == tick) ? tick : floored + spacing;
    }

    function token1ToToken0(
        uint256 amount1,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256) {
        if (sqrtPriceX96 == 0) revert InvalidPoolPrice();
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        return
            Math.mulDiv(
                Math.mulDiv(amount1, 1 << 96, sqrtPrice),
                1 << 96,
                sqrtPrice
            );
    }

    function token0ToToken1(
        uint256 amount0,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 temp = Math.mulDiv(amount0, sqrtPrice, uint256(1) << 96);
        return Math.mulDiv(temp, sqrtPrice, uint256(1) << 96);
    }

    function computeOptimalSwap(
        uint160 sqrtP,
        uint160 sqrtA,
        uint160 sqrtB,
        uint256 balance0,
        uint256 balance1
    ) internal pure returns (bool swapZeroForOne, uint256 swapAmount) {
        // Price outside the target range → the position needs only one token.
        if (sqrtP <= sqrtA) return (false, balance1); // below range: all token0 → sell all token1
        if (sqrtP >= sqrtB) return (true, balance0); //  above range: all token1 → sell all token0

        // ── In range: swap the minimum needed to reach the range's value ratio. ──
        // At the current price the range wants token0 and token1 in proportion
        // (need0 : need1) per unit of liquidity. We compare the *value* of what we
        // hold against that target split and swap only the difference. Working in
        // token1 (value) units — converting via the spot price — keeps this correct
        // regardless of the token prices (e.g. 1 BTC ≈ tens of thousands of MUSD) and
        // never degenerates to "swap everything" when one balance is zero.
        uint128 lRef = 1e18; // reference liquidity; cancels out, used only for the ratio
        uint256 need0 = LiquidityAmounts.getAmount0ForLiquidity(
            sqrtP,
            sqrtB,
            lRef
        );
        uint256 need1 = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtA,
            sqrtP,
            lRef
        );

        uint256 need0InT1 = token0ToToken1(need0, sqrtP); // token0 leg valued in token1
        uint256 targetDen = need0InT1 + need1; // total target value (token1 units)
        if (targetDen == 0) return (false, 0);

        uint256 v0 = token0ToToken1(balance0, sqrtP); // current token0 value, in token1
        uint256 vTot = v0 + balance1; // total holdings value, in token1
        uint256 targetV0 = Math.mulDiv(
            vTot,
            need0InT1,
            targetDen,
            Math.Rounding.Floor
        );

        if (v0 > targetV0) {
            // Too much token0 → sell the excess token0 value for token1.
            uint256 excessValue = v0 - targetV0; // token1 units
            swapAmount = token1ToToken0(excessValue, sqrtP); // → token0 amount to sell
            if (swapAmount > balance0) swapAmount = balance0;
            return (true, swapAmount);
        } else {
            // Too little token0 → sell token1 for token0. Value-in-token1 == token1 amount.
            uint256 deficitValue = targetV0 - v0;
            if (deficitValue > balance1) deficitValue = balance1;
            return (false, deficitValue);
        }
    }

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
            (exp0, exp1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtTwap,
                sqrtLower,
                sqrtUpper,
                liquidity
            );
        } else {
            uint128 expectedLiq = LiquidityAmounts.getLiquidityForAmounts(
                sqrtTwap,
                sqrtLower,
                sqrtUpper,
                amount0,
                amount1
            );
            (exp0, exp1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtTwap,
                sqrtLower,
                sqrtUpper,
                expectedLiq
            );
        }

        min0 = Math.mulDiv(
            exp0,
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
        min1 = Math.mulDiv(
            exp1,
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
    }

    function computeSwapMinOut(
        uint256 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceX96,
        uint256 slippageBps
    ) internal pure returns (uint256 minOut) {
        uint256 expected = zeroForOne
            ? token0ToToken1(amountIn, sqrtPriceX96)
            : token1ToToken0(amountIn, sqrtPriceX96);
        minOut = Math.mulDiv(
            expected,
            10_000 - slippageBps,
            10_000,
            Math.Rounding.Floor
        );
    }
}
