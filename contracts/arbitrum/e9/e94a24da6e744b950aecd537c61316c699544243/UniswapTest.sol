// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IWNT } from "./IWNT.sol";
import { ISwapRouter } from "./ISwapRouter.sol";

interface IChainlinkOracle {
  function consultIn18Decimals(address token) external view returns (uint256);
}

contract UniswapTest {
  using SafeERC20 for IERC20;

  struct SwapParams {
    // Address of token in
    address tokenIn;
    // Address of token out
    address tokenOut;
    // Amount of token in; in token decimals
    uint256 amountIn;
    // Fee in LP pool, 500 = 0.05%, 3000 = 0.3%
    uint256 poolFee;
    // Slippage tolerance swap; e.g. 3 = 0.03%
    uint256 slippage;
    // Swap deadline timestamp
    uint256 deadline;
  }

  SwapParams internal _sp;
  ISwapRouter.ExactInputParams internal _eip;


  address public WNT = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public tokenA = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public tokenB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
  address public univ3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address public chainlinkOracle = 0xE76bd8B1A7E054691E0d3deB744B201c71D18C5C;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;


  /* ========== MUTATIVE FUNCTIONS ========== */

  function getSp() external view returns (SwapParams memory) {
    return _sp;
  }

  function getEip() external view returns (ISwapRouter.ExactInputParams memory) {
    return _eip;
  }

  function swap(SwapParams memory sp) public {
    _sp = sp;

    IERC20(sp.tokenIn).safeTransferFrom(
      msg.sender,
      address(this),
      sp.amountIn
    );

    IERC20(sp.tokenIn).approve(
      univ3Router,
      IERC20(sp.tokenIn).balanceOf(address(this))
    );

    // Get quote amountOut

    uint256 _tokenInValue = IChainlinkOracle(chainlinkOracle).consultIn18Decimals(sp.tokenIn);
    uint256 _tokenOutValue =IChainlinkOracle(chainlinkOracle).consultIn18Decimals(sp.tokenOut);

    uint256 _amountInValue = _tokenInValue * sp.amountIn / SAFE_MULTIPLIER;
    uint256 _amountOutMinimum = _amountInValue * SAFE_MULTIPLIER / _tokenOutValue * (10000 - sp.slippage) / 10000;

    ISwapRouter.ExactInputParams memory _params =
      ISwapRouter.ExactInputParams({
          path: abi.encodePacked(sp.tokenIn, uint24(sp.poolFee), WNT, uint24(500), sp.tokenOut),
          recipient: address(this),
          deadline: sp.deadline,
          amountIn: sp.amountIn,
          amountOutMinimum: _amountOutMinimum
      });

    _eip = _params;

    ISwapRouter(univ3Router).exactInput(_params);

    IERC20(sp.tokenOut).safeTransfer(
      msg.sender,
      IERC20(sp.tokenOut).balanceOf(address(this))
    );
  }

  function swapSingle(
    address tokenIn,
    address tokenOut,
    uint24 fee,
    address recipient,
    uint256 deadline,
    uint256 amountIn,
    uint256 amountOutMinimum
  ) public {

    IERC20(tokenIn).safeTransferFrom(
      msg.sender,
      address(this),
      amountIn
    );

    IERC20(tokenIn).approve(
      univ3Router,
      amountIn
    );

    ISwapRouter.ExactInputSingleParams memory _params =
      ISwapRouter.ExactInputSingleParams({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        fee: fee,
        recipient: recipient,
        deadline: deadline,
        amountIn: amountIn,
        amountOutMinimum: amountOutMinimum,
        sqrtPriceLimitX96: 0
      });

    ISwapRouter(univ3Router).exactInputSingle(_params);
  }

  function swapMultiple(
    address tokenIn,
    bytes calldata path,
    address recipient,
    uint256 deadline,
    uint256 amountIn,
    uint256 amountOutMinimum
  ) public {

    IERC20(tokenIn).safeTransferFrom(
      msg.sender,
      address(this),
      amountIn
    );

    IERC20(tokenIn).approve(
      univ3Router,
      amountIn
    );

    ISwapRouter.ExactInputParams memory _params =
      ISwapRouter.ExactInputParams({
          path: path,
          recipient: recipient,
          deadline: deadline,
          amountIn: amountIn,
          amountOutMinimum: amountOutMinimum
      });

    _eip = _params;

    ISwapRouter(univ3Router).exactInput(_params);
  }

  receive() external payable {

  }
}

