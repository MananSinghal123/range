// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/interfaces/pool/ICLPool.sol";

/// @dev Mock CLPool that mirrors the real CLPool's initialize() pattern.
///      No constructor — state is set via initialize() just like the real clone.
contract MockCLPool {
    // ── Storage ───────────────────────────────────────────────────────────────
    // Use override so they satisfy ICLPool interface getter requirements
    address public token0;
    address public token1;
    int24 public tickSpacing;

    // Store slot0 fields with underscore prefix to avoid name clash with slot0()
    uint160 internal _sqrtPriceX96;
    int24 internal _tick;
    uint16 internal _observationIndex;
    uint16 internal _observationCardinality;
    uint16 internal _observationCardinalityNext;
    bool internal _unlocked;

    bool private _initialized;

    // ── Initialize — mirrors CLFactory.createPool() → CLPool.initialize() ────
    /// @param _factory          ignored in mock
    /// @param _token0           token0 address
    /// @param _token1           token1 address
    /// @param _tickSpacing      tick spacing for the pool
    /// @param _factoryRegistry  ignored in mock
    /// @param sqrtPriceX96      initial sqrt price in Q96 format
    function initialize(
        address _factory,
        address _token0,
        address _token1,
        int24 _tickSpacing,
        address _factoryRegistry,
        uint160 sqrtPriceX96
    ) external {
        require(!_initialized, "MockCLPool: already initialized");
        _initialized = true;

        token0 = _token0;
        token1 = _token1;
        tickSpacing = _tickSpacing;

        // Real CLPool calls TickMath.getTickAtSqrtRatio() here for tick.
        // In mock, tick defaults to 0 — caller sets correct value via setPrice()
        _sqrtPriceX96 = sqrtPriceX96;
        _tick = 0;
        _observationIndex = 0;
        _observationCardinality = 1;
        _observationCardinalityNext = 1;
        _unlocked = true;
    }

    // ── ICLPool interface ─────────────────────────────────────────────────────

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            bool unlocked
        )
    {
        return (
            _sqrtPriceX96,
            _tick,
            _observationIndex,
            _observationCardinality,
            _observationCardinalityNext,
            _unlocked
        );
    }

    /// @dev Returns tick cumulatives as if the pool ticked at _tick continuously.
    ///      This makes _getTwapTick() return exactly the current spot tick so
    ///      _requireSpotNearTwap() always passes in tests.
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        )
    {
        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            uint32 t = uint32(block.timestamp) - secondsAgos[i];
            tickCumulatives[i] = int56(_tick) * int56(uint56(t));
        }
    }

    // ── Test control methods ──────────────────────────────────────────────────

    /// @dev Simulate price movement. Call after initialize() to set correct tick.
    function setPrice(uint160 sqrtPriceX96_, int24 tick_) external {
        _sqrtPriceX96 = sqrtPriceX96_;
        _tick = tick_;
    }

    function setTickSpacing(int24 spacing) external {
        tickSpacing = spacing;
    }

    function setUnlocked(bool unlocked_) external {
        _unlocked = unlocked_;
    }

    function isInitialized() external view returns (bool) {
        return _initialized;
    }
}
