// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { IChainlinkOracle } from "./IChainlinkOracle.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { ISwap } from "./ISwap.sol";

contract Uniswap is ISwap {

  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  // Address of uniswap router
  ISwapRouter public router;
  // Address of chainlink oracle
  IChainlinkOracle public oracle;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _router Address of router of swap
  */
  constructor(ISwapRouter _router, IChainlinkOracle _oracle) {
    router = ISwapRouter(_router);
    oracle = IChainlinkOracle(_oracle);
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

    uint256 _valueIn = sp.amountIn * oracle.consultIn18Decimals(sp.tokenIn) / SAFE_MULTIPLIER;

    uint256 _amountOutMinimum = _valueIn
      * SAFE_MULTIPLIER
      / oracle.consultIn18Decimals(sp.tokenOut)
      / (10 ** (18 - IERC20Metadata(sp.tokenOut).decimals()))
      * (10000 - sp.slippage) / 10000;

    ISwapRouter.ExactInputSingleParams memory _eisp =
      ISwapRouter.ExactInputSingleParams({
        tokenIn: sp.tokenIn,
        tokenOut: sp.tokenOut,
        fee: sp.fee,
        recipient: address(this),
        deadline: sp.deadline,
        amountIn: sp.amountIn,
        amountOutMinimum: _amountOutMinimum,
        sqrtPriceLimitX96: 0
      });

    router.exactInputSingle(_eisp);

    uint256 _amountOut = IERC20(sp.tokenOut).balanceOf(address(this));

    IERC20(sp.tokenOut).safeTransfer(msg.sender, _amountOut);

    return _amountOut;
  }
}

