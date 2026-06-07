// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICLSwapRouter} from "../../src/interfaces/router/ICLSwapRouter.sol";

contract CLSwapRouterForkTest is Test {
    ICLSwapRouter constant ROUTER =
        ICLSwapRouter(0x3112908bB72ce9c26a321Eeb22EC8e051F3b6E6a);

    address constant TOKEN0 = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503; // MUSD
    address constant TOKEN1 = 0x7b7C000000000000000000000000000000000000; // BTC
    int24 constant TICK_SPACING = 50;

    address trader;

    function setUp() public {
        vm.createSelectFork("https://rpc.test.mezo.org");
        trader = makeAddr("trader");
        deal(TOKEN0, trader, 100e18);
    }

    function test_token0_approve() public {
        uint256 amountIn = 10e18;

        vm.startPrank(trader);
        IERC20(TOKEN0).approve(address(ROUTER), amountIn);
        uint256 allowance = IERC20(TOKEN0).allowance(trader, address(ROUTER));

        assertEq(allowance, amountIn, "allowance mismatch");
        vm.stopPrank();
    }

    function test_token1_approve() public {
        uint256 amountIn = 10e18;

        vm.startPrank(trader);
        (bool success, bytes memory data) = TOKEN1.call(
            abi.encodeWithSelector(
                IERC20.approve.selector,
                address(ROUTER),
                amountIn
            )
        );

        console.log("success", success);
        vm.stopPrank();
    }

    function test_exactInputSingle_token0ForToken1() public {
        uint256 amountIn = 10e18;

        console.log("Testing exactInputSingle with TOKEN0 -> TOKEN1");

        vm.startPrank(trader);
        IERC20(TOKEN0).approve(address(ROUTER), amountIn);
        console.log(
            "Trader TOKEN0 balance before:",
            IERC20(TOKEN0).balanceOf(trader)
        );

        (bytes memory data) = abi.encodeWithSelector(
            IERC20.balanceOf.selector,
            trader
        );

        (bool success, bytes memory result) = TOKEN1.call(data);
        uint256 amountOut = ROUTER.exactInputSingle(
            ICLSwapRouter.ExactInputSingleParams({
                tokenIn: TOKEN0,
                tokenOut: TOKEN1,
                tickSpacing: TICK_SPACING,
                recipient: trader,
                deadline: block.timestamp + 300,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();

        // uint256 after1 = IERC20(TOKEN1).balanceOf(trader);
        // assertGt(amountOut, 0, "no output");
        // assertEq(after1 - before1, amountOut, "balance delta mismatch");
        // console.log("TOKEN0 in:", amountIn);
        // console.log("TOKEN1 out:", amountOut);
    }

    // function test_exactInputSingle_reducesToken0Balance() public {
    //     uint256 amountIn = 5e18;

    //     vm.startPrank(trader);
    //     IERC20(TOKEN0).approve(address(ROUTER), amountIn);

    //     uint256 before0 = IERC20(TOKEN0).balanceOf(trader);

    //     ROUTER.exactInputSingle(
    //         ICLSwapRouter.ExactInputSingleParams({
    //             tokenIn: TOKEN0,
    //             tokenOut: TOKEN1,
    //             tickSpacing: TICK_SPACING,
    //             recipient: trader,
    //             deadline: block.timestamp + 300,
    //             amountIn: amountIn,
    //             amountOutMinimum: 0,
    //             sqrtPriceLimitX96: 0
    //         })
    //     );
    //     vm.stopPrank();

    //     uint256 after0 = IERC20(TOKEN0).balanceOf(trader);
    //     assertEq(before0 - after0, amountIn, "input token not fully consumed");
    // }

    function test_exactInputSingle_revertsAfterDeadline() public {
        uint256 amountIn = 1e18;

        vm.startPrank(trader);
        IERC20(TOKEN0).approve(address(ROUTER), amountIn);

        vm.expectRevert();
        ROUTER.exactInputSingle(
            ICLSwapRouter.ExactInputSingleParams({
                tokenIn: TOKEN0,
                tokenOut: TOKEN1,
                tickSpacing: TICK_SPACING,
                recipient: trader,
                deadline: block.timestamp - 1,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }

    function test_exactInputSingle_revertsIfAmountOutBelowMinimum() public {
        uint256 amountIn = 1e18;

        vm.startPrank(trader);
        IERC20(TOKEN0).approve(address(ROUTER), amountIn);

        vm.expectRevert();
        ROUTER.exactInputSingle(
            ICLSwapRouter.ExactInputSingleParams({
                tokenIn: TOKEN0,
                tokenOut: TOKEN1,
                tickSpacing: TICK_SPACING,
                recipient: trader,
                deadline: block.timestamp + 300,
                amountIn: amountIn,
                amountOutMinimum: type(uint256).max, // impossible minimum
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }

    // function test_exactInputSingle_differentRecipient() public {
    //     uint256 amountIn = 2e18;
    //     address recipient = makeAddr("recipient");

    //     vm.startPrank(trader);
    //     IERC20(TOKEN0).approve(address(ROUTER), amountIn);

    //     uint256 amountOut = ROUTER.exactInputSingle(
    //         ICLSwapRouter.ExactInputSingleParams({
    //             tokenIn: TOKEN0,
    //             tokenOut: TOKEN1,
    //             tickSpacing: TICK_SPACING,
    //             recipient: recipient,
    //             deadline: block.timestamp + 300,
    //             amountIn: amountIn,
    //             amountOutMinimum: 0,
    //             sqrtPriceLimitX96: 0
    //         })
    //     );
    //     vm.stopPrank();

    //     assertGt(
    //         IERC20(TOKEN1).balanceOf(recipient),
    //         0,
    //         "recipient got nothing"
    //     );
    //     assertEq(
    //         IERC20(TOKEN1).balanceOf(recipient),
    //         amountOut,
    //         "recipient balance mismatch"
    //     );
    // }
}
