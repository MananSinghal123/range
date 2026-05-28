// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/interfaces/ICLSwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockCLSwapRouter {
    using SafeERC20 for IERC20;

    // Configurable for testing
    uint256 public amountOutReturn;
    bool public shouldRevert;
    bool public shouldReturnLessThanMin; // simulate slippage exceed

    uint256 public swapCallCount;

    function setAmountOut(uint256 amount) external {
        amountOutReturn = amount;
    }

    function setShouldRevert(bool revert_) external {
        shouldRevert = revert_;
    }

    function setShouldReturnLessThanMin(bool val) external {
        shouldReturnLessThanMin = val;
    }

    function exactInputSingle(
        ICLSwapRouter.ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut) {
        if (shouldRevert) revert("MockRouter: swap reverted");

        // Pull tokenIn
        IERC20(params.tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );

        if (amountOutReturn > 0) {
            amountOut = amountOutReturn;
        } else if (shouldReturnLessThanMin) {
            amountOut = params.amountOutMinimum - 1;
        } else {
            // Default: return amountIn as a stand-in; skip minimum check so
            // callers that haven't configured the mock don't get spurious failures.
            amountOut = params.amountIn;
            IERC20(params.tokenOut).safeTransfer(params.recipient, amountOut);
            swapCallCount++;
            return amountOut;
        }

        if (amountOut < params.amountOutMinimum)
            revert("MockRouter: insufficient output");

        IERC20(params.tokenOut).safeTransfer(params.recipient, amountOut);
        swapCallCount++;
    }
}
