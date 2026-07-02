// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LiquidityAmounts, TickMath} from "./libraries/UniswapV3Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OracleLib} from "./libraries/OracleLib.sol";
import {IDexAdapter} from "./adapters/interfaces/IDexAdapter.sol";
import {IStrategy} from "./strategies/interfaces/IStrategy.sol";

/// @notice Minimal interface for the vault public getters used by VaultLens.
interface IVaultView {
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function tokenId() external view returns (uint256);
    function pool() external view returns (address);
    function positionManager() external view returns (address);
    function dexAdapter() external view returns (address);
    function strategy() external view returns (address);
    function twapSeconds() external view returns (uint32);
    function rebalanceCount() external view returns (uint256);
    function totalFees0Earned() external view returns (uint256);
    function totalFees1Earned() external view returns (uint256);
}

/// @title VaultLens
/// @notice Stateless off-chain helper. Deploy once; point at any
///         RebalancerVaultUpgradeable by passing its address.
contract VaultLens {
    // ─── Structs ─────────────────────────────────────────────────────────────────

    struct VaultMetrics {
        uint256 tvl;
        int24 tickLower;
        int24 tickUpper;
        uint256 rebalanceCount;
        uint256 totalFees0Earned;
        uint256 totalFees1Earned;
    }

    struct PositionInfo {
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    // ─── View functions ──────────────────────────────────────────────────────────

    /// @notice Price of one share expressed in token0 units (scaled to token0 decimals).
    function sharePrice(address vault) external view returns (uint256) {
        IVaultView v = IVaultView(vault);
        uint256 supply = v.totalSupply();
        if (supply == 0) return 0;
        return
            Math.mulDiv(
                v.totalAssets(),
                10 ** v.decimals(),
                supply,
                Math.Rounding.Floor
            );
    }

    /// @notice All key vault metrics in a single call.
    function getVaultMetrics(
        address vault
    ) external view returns (VaultMetrics memory m) {
        IVaultView v = IVaultView(vault);
        m.tvl = v.totalAssets();
        m.rebalanceCount = v.rebalanceCount();
        m.totalFees0Earned = v.totalFees0Earned();
        m.totalFees1Earned = v.totalFees1Earned();
        uint256 tid = v.tokenId();
        if (tid != 0) {
            (m.tickLower, m.tickUpper, , , , , ) = _positions(v, tid);
        }
    }

    /// @notice Current pool price and tick from slot0.
    /// @dev WARNING: spot price — manipulable within a block. Do not use for pricing.
    function getPoolState(
        address vault
    ) external view returns (uint160 sqrtPriceX96, int24 tick) {
        IVaultView v = IVaultView(vault);
        return IDexAdapter(v.dexAdapter()).slot0(v.pool());
    }

    /// @notice Active CL position details.
    function getPosition(
        address vault
    ) external view returns (PositionInfo memory p) {
        IVaultView v = IVaultView(vault);
        uint256 tid = v.tokenId();
        require(tid != 0, "VaultLens: no position");
        (
            p.tickLower,
            p.tickUpper,
            p.liquidity,
            ,
            ,
            p.token0,
            p.token1
        ) = _positions(v, tid);
        p.tickSpacing = IDexAdapter(v.dexAdapter()).tickSpacing(v.pool());
    }

    /// @notice True when the current spot tick is outside [tickLower, tickUpper).
    function isOutOfRange(address vault) external view returns (bool) {
        IVaultView v = IVaultView(vault);
        uint256 tid = v.tokenId();
        require(tid != 0, "VaultLens: no position");
        (, int24 tick) = IDexAdapter(v.dexAdapter()).slot0(v.pool());
        (int24 lo, int24 hi, , , , , ) = _positions(v, tid);
        return tick < lo || tick >= hi;
    }

    /// @notice Optimal swap direction + amount to pass into the vault's rebalance().
    function computeRebalanceParams(
        address vault
    ) external view returns (bool swapZeroForOne, uint256 swapAmount) {
        IVaultView v = IVaultView(vault);
        uint256 tid = v.tokenId();
        require(tid != 0, "VaultLens: no position");

        address adapter = v.dexAdapter();
        address poolAddr = v.pool();

        (int24 lo, int24 hi, uint128 liq, , , address token0, address token1) =
            _positions(v, tid);
        (uint160 sqrtPriceX96, ) = IDexAdapter(adapter).slot0(poolAddr);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(lo),
                TickMath.getSqrtRatioAtTick(hi),
                liq
            );

        // Include tokens already idle in the vault (deposits + prior leftovers). When the
        // vault rebalances it removes the position and holds principal + idle together, so
        // the optimal swap must be computed against the combined balances — not the
        // position alone (which would ignore idle tokens and over-swap).
        uint256 bal0 = amount0 + IERC20(token0).balanceOf(vault);
        uint256 bal1 = amount1 + IERC20(token1).balanceOf(vault);

        int24 twapTick = OracleLib.getTwapTick(poolAddr, v.twapSeconds());
        int24 spacing = IDexAdapter(adapter).tickSpacing(poolAddr);
        address strat = v.strategy();
        (int24 rLo, int24 rHi) = IStrategy(strat).computeRange(twapTick, spacing);

        return
            IStrategy(strat).computeOptimalSwap(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(rLo),
                TickMath.getSqrtRatioAtTick(rHi),
                bal0,
                bal1
            );
    }

    // ─── Internal helpers ────────────────────────────────────────────────────────

    function _positions(
        IVaultView v,
        uint256 tokenId_
    )
        internal
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1,
            address t0,
            address t1
        )
    {
        return
            IDexAdapter(v.dexAdapter()).positions(v.positionManager(), tokenId_);
    }
}
