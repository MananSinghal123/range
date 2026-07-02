// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ICLPool} from "../interfaces/pool/ICLPool.sol";
import {TickMath} from "./UniswapV3Math.sol";

library OracleLib {
    error PriceDeviatedFromTwap();

    function _twapAndSpot(
        address pool,
        uint32 twapSeconds
    ) private view returns (int24 twapTick, int24 spotTick) {
        (, spotTick, , , , ) = ICLPool(pool).slot0();

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapSeconds;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = ICLPool(pool).observe(secondsAgos);

        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        twapTick = int24(delta / int56(uint56(twapSeconds)));
    }

    function getTwapTick(
        address pool,
        uint32 twapSeconds
    ) internal view returns (int24 twapTick) {
        (twapTick, ) = _twapAndSpot(pool, twapSeconds);
    }

    function getTwapSqrtPrice(
        address pool,
        uint32 twapSeconds
    ) internal view returns (uint160) {
        return TickMath.getSqrtRatioAtTick(getTwapTick(pool, twapSeconds));
    }

    function requireSpotNearTwap(
        address pool,
        uint32 twapSeconds,
        int24 maxTwapDeviationTicks
    ) internal view {
        (int24 twapTick, int24 spotTick) = _twapAndSpot(pool, twapSeconds);
        int256 deviation = int256(spotTick) - int256(twapTick);
        if (deviation < 0) deviation = -deviation;
        if (deviation > int256(uint256(int256(maxTwapDeviationTicks))))
            revert PriceDeviatedFromTwap();
    }

    function isDepositAllowed(
        address pool,
        uint32 twapSeconds,
        int24 maxTwapDeviationTicks,
        bool paused
    ) internal view returns (bool) {
        if (paused) return false;
        (int24 twapTick, int24 spotTick) = _twapAndSpot(pool, twapSeconds);
        int256 deviation = int256(spotTick) - int256(twapTick);
        if (deviation < 0) deviation = -deviation;
        return deviation <= int256(uint256(int256(maxTwapDeviationTicks)));
    }
}
