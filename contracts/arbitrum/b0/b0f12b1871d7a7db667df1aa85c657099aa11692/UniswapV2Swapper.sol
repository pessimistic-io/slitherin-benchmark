// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./ERC20.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./TransferHelper.sol";
import "./DexSwapper.sol";

contract UniswapV2Swapper is DexSwapper {
  IUniswapV2Router02 public router;

  constructor(
    address _WETH9,
    address _WETH9_STABLE_POOL,
    IUniswapV2Router02 _router
  ) DexSwapper(_WETH9, _WETH9_STABLE_POOL) {
    router = _router;
  }

  function swap(
    address tokenIn,
    uint256 inAmount,
    address tokenOut,
    uint256 outAmountMin,
    uint24
  ) external override {
    address[] memory path = new address[](2);
    path[0] = tokenIn;
    path[1] = tokenOut;

    TransferHelper.safeTransferFrom(
      tokenIn,
      msg.sender,
      address(this),
      inAmount
    );
    uint256 _finalInAmount = ERC20(tokenIn).balanceOf(address(this));
    require(_finalInAmount >= 0, 'SWAP: need tokens to swap');

    TransferHelper.safeApprove(tokenIn, address(router), _finalInAmount);
    router.swapExactTokensForTokens(
      _finalInAmount,
      outAmountMin,
      path,
      msg.sender,
      block.timestamp
    );
  }

  function getPoolInfo(
    address _targetToken,
    address _poolAddy
  )
    external
    view
    override
    returns (
      uint24 poolFee,
      address token0,
      address token1,
      uint256 reserves0,
      uint256 reserves1,
      uint256 priceX96,
      uint256 priceUSDNoDecimalsX128
    )
  {
    IUniswapV2Pair _pool = IUniswapV2Pair(_poolAddy);
    token0 = _pool.token0();
    token1 = _pool.token1();
    uint8 token0Decimals = ERC20(token0).decimals();
    uint8 token1Decimals = ERC20(token1).decimals();
    (uint112 _res0, uint112 _res1, ) = _pool.getReserves();
    priceX96 = (_res1 * 2 ** 96) / _res0;

    priceUSDNoDecimalsX128 = _getPriceUSDOfTargetTokenNoDecimalsX128(
      _targetToken,
      priceX96,
      token0,
      token0Decimals,
      token1,
      token1Decimals
    );

    return (
      3000, // 0.3%
      token0,
      token1,
      _res0,
      _res1,
      priceX96,
      priceUSDNoDecimalsX128
    );
  }

  function _getUSDWETHNoDecimalsPriceX96()
    internal
    view
    override
    returns (uint256 usdWETHNoDecimalsX96)
  {
    IUniswapV2Pair _pool = IUniswapV2Pair(WETH9_STABLE_POOL);
    address token0 = _pool.token0();
    address token1 = _pool.token1();
    uint8 token0Decimals = ERC20(token0).decimals();
    uint8 token1Decimals = ERC20(token1).decimals();
    (uint112 _res0, uint112 _res1, ) = _pool.getReserves();
    uint256 priceX96 = (_res1 * 2 ** 96) / _res0;

    if (token0 == WETH9) {
      usdWETHNoDecimalsX96 =
        (priceX96 * 10 ** token0Decimals) /
        10 ** token1Decimals;
    } else {
      usdWETHNoDecimalsX96 =
        (2 ** (96 * 2) * 10 ** token1Decimals) /
        priceX96 /
        10 ** token0Decimals;
    }
  }
}

