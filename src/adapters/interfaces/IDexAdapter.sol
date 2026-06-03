// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title IDexAdapter
/// @notice One seam over a concentrated-liquidity DEX fork (pool + position manager + router).
///         Read fns are STATICCALLed by the vault; write fns are DELEGATECALLed so they run in
///         the vault's context (the vault keeps custody of tokens, the NFT, approvals, refunds).
///         Implementations MUST be stateless (declare no storage) to keep delegatecall safe.
interface IDexAdapter {
    struct MintArgs {
        address positionManager;
        address token0;
        address token1;
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    struct DecreaseArgs {
        address positionManager;
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    struct CollectArgs {
        address positionManager;
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
    struct SwapArgs {
        address router;
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    // ── reads (staticcall) ──
    function slot0(address pool) external view returns (uint160 sqrtPriceX96, int24 tick);
    function observe(address pool, uint32[] calldata secondsAgos)
        external view returns (int56[] memory tickCumulatives);
    function tickSpacing(address pool) external view returns (int24);
    function positions(address positionManager, uint256 tokenId) external view returns (
        int24 tickLower, int24 tickUpper, uint128 liquidity,
        uint128 tokensOwed0, uint128 tokensOwed1, address token0, address token1
    );

    // ── writes (delegatecall, in vault context) ──
    function mint(MintArgs calldata p)
        external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(DecreaseArgs calldata p) external returns (uint256 amount0, uint256 amount1);
    function collect(CollectArgs calldata p) external returns (uint256 amount0, uint256 amount1);
    function burn(address positionManager, uint256 tokenId) external;
    function exactInputSingle(SwapArgs calldata p) external returns (uint256 amountOut);
}
