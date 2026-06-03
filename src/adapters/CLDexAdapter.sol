// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDexAdapter} from "./interfaces/IDexAdapter.sol";
import {ICLPool} from "../interfaces/pool/ICLPool.sol";
import {
    INonfungiblePositionManager
} from "../interfaces/INonfungiblePositionManager.sol";
import {ICLSwapRouter} from "../interfaces/router/ICLSwapRouter.sol";

contract CLDexAdapter is IDexAdapter {
    using SafeERC20 for IERC20;

    function slot0(
        address pool
    ) external view returns (uint160 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick, , , , ) = ICLPool(pool).slot0();
    }

    function observe(
        address pool,
        uint32[] calldata secondsAgos
    ) external view returns (int56[] memory tickCumulatives) {
        (tickCumulatives, ) = ICLPool(pool).observe(secondsAgos);
    }

    function tickSpacing(address pool) external view returns (int24) {
        return ICLPool(pool).tickSpacing();
    }

    function positions(
        address positionManager,
        uint256 tokenId
    )
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1,
            address token0,
            address token1
        )
    {
        (
            ,
            ,
            token0,
            token1,
            ,
            tickLower,
            tickUpper,
            liquidity,
            ,
            ,
            tokensOwed0,
            tokensOwed1
        ) = INonfungiblePositionManager(positionManager).positions(tokenId);
    }

    function mint(
        MintArgs calldata p
    )
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        IERC20(p.token0).forceApprove(p.positionManager, p.amount0Desired);
        IERC20(p.token1).forceApprove(p.positionManager, p.amount1Desired);
        return
            INonfungiblePositionManager(p.positionManager).mint(
                INonfungiblePositionManager.MintParams({
                    token0: p.token0,
                    token1: p.token1,
                    tickSpacing: p.tickSpacing,
                    tickLower: p.tickLower,
                    tickUpper: p.tickUpper,
                    amount0Desired: p.amount0Desired,
                    amount1Desired: p.amount1Desired,
                    amount0Min: p.amount0Min,
                    amount1Min: p.amount1Min,
                    recipient: p.recipient,
                    deadline: p.deadline,
                    sqrtPriceX96: 0
                })
            );
    }

    function decreaseLiquidity(
        DecreaseArgs calldata p
    ) external returns (uint256 amount0, uint256 amount1) {
        return
            INonfungiblePositionManager(p.positionManager).decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: p.tokenId,
                    liquidity: p.liquidity,
                    amount0Min: p.amount0Min,
                    amount1Min: p.amount1Min,
                    deadline: p.deadline
                })
            );
    }

    function collect(
        CollectArgs calldata p
    ) external returns (uint256 amount0, uint256 amount1) {
        return
            INonfungiblePositionManager(p.positionManager).collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: p.tokenId,
                    recipient: p.recipient,
                    amount0Max: p.amount0Max,
                    amount1Max: p.amount1Max
                })
            );
    }

    function burn(address positionManager, uint256 tokenId) external {
        INonfungiblePositionManager(positionManager).burn(tokenId);
    }

    function exactInputSingle(
        SwapArgs calldata p
    ) external returns (uint256 amountOut) {
        IERC20(p.tokenIn).forceApprove(p.router, p.amountIn);
        return
            ICLSwapRouter(p.router).exactInputSingle(
                ICLSwapRouter.ExactInputSingleParams({
                    tokenIn: p.tokenIn,
                    tokenOut: p.tokenOut,
                    tickSpacing: p.tickSpacing,
                    recipient: p.recipient,
                    deadline: p.deadline,
                    amountIn: p.amountIn,
                    amountOutMinimum: p.amountOutMinimum,
                    sqrtPriceLimitX96: 0
                })
            );
    }
}
