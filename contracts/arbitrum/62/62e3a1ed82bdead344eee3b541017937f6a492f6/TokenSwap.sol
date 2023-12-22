//  SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IV3SwapRouter} from "./IV3SwapRouter.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {GLPHelper} from "./GLPHelper.sol";
import {PriceHelper} from "./PriceHelper.sol";
import {Addresses} from "./Addresses.sol";

library TokenSwap {
  using GLPHelper for IERC20;
  using PriceHelper for IERC20;
  IV3SwapRouter public constant swapRouter = IV3SwapRouter(Addresses.swapRouter);

  function getAmountOutMin(
    // 10000*100: 500 is .05% fee
    uint amountIn,
    uint24 fee,
    uint24 maxSlippage
  ) public pure returns (uint) {
    uint totalBps = 1000000;
    uint afterFee = amountIn * (totalBps - fee) / totalBps;
    return afterFee*(totalBps - maxSlippage)/totalBps;
  }

  function swap(
    IERC20 tokenIn,
    IERC20 tokenOut,
    uint amount,
    uint24 fee,
    uint24 maxSlippage
  ) internal returns (uint amountOut) {
    require(maxSlippage <= 1000000, "maxSlippage cannot be greater than 100%");
    uint amountOutBase = PriceHelper.getTokensForNumTokens(tokenIn, amount, tokenOut);
    uint minOut = getAmountOutMin(amountOutBase, fee, maxSlippage);

    if(tokenIn == GLPHelper.fsGLP) {
      amountOut = GLPHelper.unstake(tokenOut, amount, minOut);
    }
    else if(tokenOut == GLPHelper.fsGLP) {
      amountOut = GLPHelper.mintAndStake(tokenIn, amount, 0, minOut);
    }
    else if(tokenIn != tokenOut) {
      require(fee >= 100, 'fee cannot be less than .01%');
      amountOut = swapTokens(
        tokenIn,
        tokenOut,
        amount,
        fee,
        minOut
      );
    }
    else {
      amountOut = amount;
    }
    return amountOut;
  }

  function swapTokens(
    IERC20 tokenIn,
    IERC20 tokenOut,
    uint amount,
    uint24 fee,
    uint amountOutMin
  ) internal returns (uint256 amountOut) {
    tokenIn.approve(address(swapRouter), amount);
    IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
      tokenIn: address(tokenIn),
      tokenOut: address(tokenOut),
      fee: fee,
      recipient: address(this),
      amountIn: amount,
      amountOutMinimum: amountOutMin,
      sqrtPriceLimitX96: 0
    });
    amountOut = swapRouter.exactInputSingle(params);
  }
}

