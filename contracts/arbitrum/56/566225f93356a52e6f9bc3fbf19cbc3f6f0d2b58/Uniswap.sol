// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { ISwap } from "./ISwap.sol";

contract Uniswap is ISwap {

  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  ISwapRouter public router;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _router Address of router of swap
  */
  constructor(ISwapRouter _router) {
    router = ISwapRouter(_router);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Swap tokens
    * @param sp SwapParams struct
    * @return amountOut Amount of tokens out in token decimals
  */
  function swap(
    ISwap.SwapParams memory sp
  ) external returns (uint256) {
    IERC20(sp.tokenIn).safeTransferFrom(msg.sender, address(this), sp.amountIn);

    IERC20(sp.tokenIn).approve(address(router), sp.amountIn);

    // TODO Calculate amountOutMinimum using slippage

    ISwapRouter.ExactInputSingleParams memory _eisp =
      ISwapRouter.ExactInputSingleParams({
        tokenIn: sp.tokenIn,
        tokenOut: sp.tokenOut,
        fee: sp.fee,
        recipient: address(this),
        deadline: sp.deadline,
        amountIn: sp.amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });

    uint256 _amountOut = router.exactInputSingle(_eisp);

    IERC20(sp.tokenOut).safeTransfer(msg.sender, IERC20(sp.tokenOut).balanceOf(address(this)));

    return _amountOut;
  }
}

