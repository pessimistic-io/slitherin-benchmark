// SPDX-License-Identifier: Do-Whatever-You-Want-With-This-License
pragma solidity ^0.8.9;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";

contract TokenSwapper {
    ISwapRouter public immutable swapRouter; //= address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 public constant feeTier = 3000;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }
    
    function swapToken(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {

        // Transfer the specified amount of WETH9 to this contract.
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        // Approve the router to spend WETH9.
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: feeTier,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }
}

