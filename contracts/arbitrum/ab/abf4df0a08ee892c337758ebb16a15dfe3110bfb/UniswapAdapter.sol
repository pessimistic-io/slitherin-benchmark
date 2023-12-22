// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

import {ISwapRouter} from "./ISwapRouter.sol";
import {TransferHelper} from "./TransferHelper.sol";
import {IERC20} from "./IERC20.sol";

abstract contract UniswapAdapter {
    ISwapRouter public immutable swapRouter;

    struct UniswapV3Single {
        uint256 amountIn;
        uint256 amountOutMin;
        address token1;
        address token2;
        uint24 poolFee;
    }

    struct UniswapV3Multi {
        uint256 amountIn;
        uint256 amountOutMin;
        address token1;
        address token2;
        address token3;
        uint24 fee1;
        uint24 fee2;
    }

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    function swapExactInputSingle(UniswapV3Single memory swapParams) internal returns (uint256 amountOut) {
        // msg.sender must approve this contract

        // Approve the router to spend token1.
        TransferHelper.safeApprove(
            swapParams.token1, address(swapRouter), IERC20(swapParams.token1).balanceOf(address(this))
        );

        // set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: swapParams.token1,
            tokenOut: swapParams.token2,
            fee: swapParams.poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: swapParams.amountIn,
            amountOutMinimum: swapParams.amountOutMin,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its token1 for this function to succeed.
    function swapExactInputMultihop(UniswapV3Multi memory multiParams) internal returns (uint256 amountOut) {
        // Approve the router to spend token1.
        TransferHelper.safeApprove(
            multiParams.token1, address(swapRouter), IERC20(multiParams.token1).balanceOf(address(this))
        );

        // Multiple pool swaps are encoded through bytes called a `path`. A path is a sequence of token addresses and poolFees that define the pools used in the swaps.
        // The format for pool encoding is (tokenIn, fee, tokenOut/tokenIn, fee, tokenOut) where tokenIn/tokenOut parameter is the shared token across the pools.
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(
                multiParams.token1, multiParams.fee1, multiParams.token2, multiParams.fee2, multiParams.token3
                ),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: multiParams.amountIn,
            amountOutMinimum: multiParams.amountOutMin
        });

        // Executes the swap.
        amountOut = swapRouter.exactInput(params);
    }
}

