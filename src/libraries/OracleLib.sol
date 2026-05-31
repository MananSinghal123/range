// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {ICLPool} from "../interfaces/ICLPool.sol";

/// @title OracleLib
/// @notice TWAP oracle helpers extracted verbatim from the monolith. Pure functions of
///         (pool, twapSeconds, maxTwapDeviationTicks) — no contract state. Pricing decisions
///         MUST use these (never slot0 directly).
library OracleLib {
    error PriceDeviatedFromTwap();

    /// @notice TWAP tick over `twapSeconds`, with the monolith's sign-disambiguation against spot.
    function getTwapTick(address pool, uint32 twapSeconds) internal view returns (int24 twapTick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapSeconds;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = ICLPool(pool).observe(secondsAgos);

        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        twapTick = int24(delta / int56(uint56(twapSeconds)));

        (, int24 spotTick, , , , ) = ICLPool(pool).slot0();
        int24 negTwap = -twapTick;
        int256 d1 = int256(twapTick) - int256(spotTick);
        int256 d2 = int256(negTwap) - int256(spotTick);
        if (d1 < 0) d1 = -d1;
        if (d2 < 0) d2 = -d2;
        if (d2 < d1) twapTick = negTwap;
    }

    /// @notice sqrt price (Q96) at the TWAP tick.
    function getTwapSqrtPrice(address pool, uint32 twapSeconds) internal view returns (uint160) {
        return TickMath.getSqrtRatioAtTick(getTwapTick(pool, twapSeconds));
    }

    /// @notice Reverts when |spotTick - twapTick| exceeds maxTwapDeviationTicks.
    function requireSpotNearTwap(
        address pool,
        uint32 twapSeconds,
        int24 maxTwapDeviationTicks
    ) internal view {
        (, int24 spotTick, , , , ) = ICLPool(pool).slot0();
        int24 twapTick = getTwapTick(pool, twapSeconds);
        int256 deviation = int256(spotTick) - int256(twapTick);
        if (deviation < 0) deviation = -deviation;
        if (deviation > int256(uint256(int256(maxTwapDeviationTicks))))
            revert PriceDeviatedFromTwap();
    }

    /// @notice True when not paused and spot is within deviation tolerance of TWAP.
    function isDepositAllowed(
        address pool,
        uint32 twapSeconds,
        int24 maxTwapDeviationTicks,
        bool paused
    ) internal view returns (bool) {
        if (paused) return false;
        (, int24 spotTick, , , , ) = ICLPool(pool).slot0();
        int24 twapTick = getTwapTick(pool, twapSeconds);
        int256 deviation = int256(spotTick) - int256(twapTick);
        if (deviation < 0) deviation = -deviation;
        return deviation <= int256(uint256(int256(maxTwapDeviationTicks)));
    }
}
