// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable not-rely-on-time */

import "./IERC20Metadata.sol";

import "./ISwapRouter.sol";
import "./IPeripheryPayments.sol";

abstract contract UniswapHelper {
  event UniswapReverted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin);

  uint256 private constant PRICE_DENOMINATOR = 1e26;

  /// @notice 0.3% of pool fee
  uint24 private constant poolFee = 3000;

  uint8 private constant slippage = 50;

  /// @notice Minimum native asset amount to receive from a single swap, 0.01 wei
  uint256 private constant minSwapAmount = 1e16;

  /// @notice The Uniswap V3 SwapRouter contract
  ISwapRouter public immutable uniswap;

  /// @notice The ERC-20 token that wraps the native asset for current chain
  IERC20Metadata public immutable wrappedNative;

  constructor(IERC20Metadata _wrappedNative, ISwapRouter _uniswap) {
    wrappedNative = _wrappedNative;
    uniswap = _uniswap;
  }

  modifier canSwap() {
    require(address(uniswap) != address(0), "Not supported to swap");
    _;
  }

  function _maybeSwapTokenToWNative(IERC20Metadata tokenIn, uint256 amount, uint256 quote) internal returns (uint256) {
    tokenIn.approve(address(uniswap), amount);

    IERC20Metadata token = IERC20Metadata(address(tokenIn));
    uint256 amountOutMin = addSlippage(tokenToWei(token, amount, quote), slippage);
    if (amountOutMin < minSwapAmount) {
      return 0;
    }
    // note: calling 'swapToToken' but destination token is Wrapped Ether
    return swapToToken(address(tokenIn), address(wrappedNative), amount, amountOutMin, poolFee);
  }

  function addSlippage(uint256 amount, uint8 _slippage) private pure returns (uint256) {
    return (amount * (1000 - _slippage)) / 1000;
  }

  function tokenToWei(IERC20Metadata token, uint256 amount, uint256 price) public view returns (uint256) {
    uint256 nativeDecimal = 10 ** 18;
    uint256 tokenDecimal = 10 ** token.decimals();
    return (amount * nativeDecimal * price) / (PRICE_DENOMINATOR * tokenDecimal);
  }

  function weiToToken(IERC20Metadata token, uint256 amount, uint256 price) public view returns (uint256) {
    uint256 nativeDecimal = 10 ** 18;
    uint256 tokenDecimal = 10 ** token.decimals();
    return (amount * tokenDecimal * PRICE_DENOMINATOR) / (price * nativeDecimal);
  }

  // turn ERC-20 tokens into wrapped ETH at market price
  function swapToWeth(
    address tokenIn,
    address wethOut,
    uint256 amountOut,
    uint24 fee
  ) internal returns (uint256 amountIn) {
    ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
      tokenIn,
      wethOut, //tokenOut
      fee,
      address(uniswap), //recipient - keep WETH at SwapRouter for withdrawal
      block.timestamp, //deadline
      amountOut,
      type(uint256).max,
      0
    );
    amountIn = uniswap.exactOutputSingle(params);
  }

  function unwrapWeth(uint256 amount) internal {
    IPeripheryPayments(address(uniswap)).unwrapWETH9(amount, address(this));
  }

  // swap ERC-20 tokens at market price
  function swapToToken(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    uint24 fee
  ) internal returns (uint256 amountOut) {
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
      tokenIn, //tokenIn
      tokenOut, //tokenOut
      fee,
      address(uniswap),
      block.timestamp, //deadline
      amountIn,
      amountOutMin,
      0
    );
    try uniswap.exactInputSingle(params) returns (uint256 _amountOut) {
      amountOut = _amountOut;
    } catch {
      emit UniswapReverted(tokenIn, tokenOut, amountIn, amountOutMin);
      amountOut = 0;
    }
  }
}

