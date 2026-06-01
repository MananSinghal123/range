// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {ICLPool} from "../interfaces/pool/ICLPool.sol";

/// @title OracleLib
/// @notice TWAP oracle helpers. Stateless — all pool state is passed as args. Pricing
///         decisions MUST use these (never slot0 directly).
/// @dev    Internal helper _twapAndSpot reads slot0 ONCE and observe ONCE per call,
///         eliminating the double-slot0 read that existed when getTwapTick (which calls
///         slot0 for disambiguation) was called inside requireSpotNearTwap (which also
///         called slot0 for the deviation check).
library OracleLib {
    error PriceDeviatedFromTwap();

    // ─── Private helpers ────────────────────────────────────────────────────────

    /// @dev Single slot0 + observe read. Returns both the disambiguated TWAP tick and the
    ///      current spot tick so callers can reuse both without a second slot0 call.
    function _twapAndSpot(
        address pool,
        uint32 twapSeconds
    ) private view returns (int24 twapTick, int24 spotTick) {
        // ONE slot0 read — reused for disambiguation and deviation check.
        (, spotTick, , , , ) = ICLPool(pool).slot0();

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapSeconds;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = ICLPool(pool).observe(secondsAgos);

        int56 delta = tickCumulatives[1] - tickCumulatives[0];
        twapTick = int24(delta / int56(uint56(twapSeconds)));

        // Sign-disambiguation (verbatim from the monolith): pick the candidate
        // (twapTick or -twapTick) that is closer to the current spot tick.
        int24 negTwap = -twapTick;
        int256 d1 = int256(twapTick) - int256(spotTick);
        int256 d2 = int256(negTwap) - int256(spotTick);
        if (d1 < 0) d1 = -d1;
        if (d2 < 0) d2 = -d2;
        if (d2 < d1) twapTick = negTwap;
    }

    // ─── Public interface ────────────────────────────────────────────────────────

    /// @notice Disambiguated TWAP tick over `twapSeconds`.
    function getTwapTick(
        address pool,
        uint32 twapSeconds
    ) internal view returns (int24 twapTick) {
        (twapTick, ) = _twapAndSpot(pool, twapSeconds);
    }

    /// @notice sqrt price (Q96) at the TWAP tick.
    function getTwapSqrtPrice(
        address pool,
        uint32 twapSeconds
    ) internal view returns (uint160) {
        return TickMath.getSqrtRatioAtTick(getTwapTick(pool, twapSeconds));
    }

    /// @notice Reverts when |spotTick − twapTick| > maxTwapDeviationTicks.
    /// @dev Uses a single slot0 call (via _twapAndSpot) for both disambiguation and
    ///      the deviation check — previously two separate slot0 reads.
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

    /// @notice True when not paused and spot is within deviation tolerance of TWAP.
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
