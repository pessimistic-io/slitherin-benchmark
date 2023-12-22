// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {ISwapHelper} from "./ISwapHelper.sol";

contract SwapHelper is ISwapHelper {
    using SafeERC20 for IERC20;

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address router,
        bytes calldata routerCalldata
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).safeIncreaseAllowance(router, amountIn);
        (bool success, ) = router.call(routerCalldata);

        amountOut = IERC20(tokenOut).balanceOf(address(this));
        if (!success || amountOut < minAmountOut) {
            revert SwapFailed();
        }
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
}

