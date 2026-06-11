// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICLSwapRouter} from "../../src/interfaces/router/ICLSwapRouter.sol";
import {ICLPool} from "../../src/interfaces/pool/ICLPool.sol";
import {
    RebalancerVaultUpgradeable
} from "../../src/RebalancerVaultUpgradeable.sol";

contract CLSwapRouterForkTest is Test {
    ICLSwapRouter constant ROUTER =
        ICLSwapRouter(0x37cDd11919ec3860eaD9efB8673d7476E5326225);
    ICLPool constant pool = ICLPool(0x026dB82AC7ABf60Bf1a81317c9DbD63702B85850);

    address constant TOKEN0 = 0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;
    address constant TOKEN1 = 0x7b7C000000000000000000000000000000000000;
    int24 constant TICK_SPACING = 50;

    RebalancerVaultUpgradeable constant VAULT =
        RebalancerVaultUpgradeable(
            payable(0x9b29b71829597A1B705Ea1Bab1C8B2fD00088594)
        );
    address constant VAULT_OWNER = 0xe4F4c768d628074C8a975126D517a60A03848f69;

    // tick range at ~100k MUSD/BTC, spacing 50
    int24 constant TICK_LOWER = -114750;
    int24 constant TICK_UPPER = -113300;

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

    function test_initializePosition_mintsPosition() public {
        assertEq(VAULT.tokenId(), 0, "position already exists");

        vm.prank(VAULT_OWNER);
        VAULT.initializePosition(
            TICK_LOWER,
            TICK_UPPER,
            1e18, // amount0Desired (MUSD)
            100000, // amount1Desired (BTC sats)
            0,
            0
        );

        assertGt(VAULT.tokenId(), 0, "tokenId not set");
    }

}
