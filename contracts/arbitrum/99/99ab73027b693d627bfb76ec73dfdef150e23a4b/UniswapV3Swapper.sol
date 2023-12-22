// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./ERC20.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./FixedPoint96.sol";
import "./FullMath.sol";
import "./ISwapRouter.sol";
import "./TransferHelper.sol";
import "./DexSwapper.sol";

contract UniswapV3Swapper is DexSwapper {
  ISwapRouter public immutable swapRouter;

  constructor(
    address _WETH9,
    address _WETH9_STABLE_POOL,
    ISwapRouter _swapRouter
  ) DexSwapper(_WETH9, _WETH9_STABLE_POOL) {
    swapRouter = _swapRouter;
  }

  function swap(
    address tokenIn,
    uint256 inAmount,
    address tokenOut,
    uint256 outAmountMin,
    uint24 poolFee
  ) external override {
    TransferHelper.safeTransferFrom(
      tokenIn,
      msg.sender,
      address(this),
      inAmount
    );
    uint256 _finalInAmount = ERC20(tokenIn).balanceOf(address(this));
    require(_finalInAmount >= 0, 'SWAP: need tokens to swap');

    TransferHelper.safeApprove(tokenIn, address(swapRouter), _finalInAmount);
    uint256 amountOut0 = swapRouter.exactInputSingle(
      ISwapRouter.ExactInputSingleParams({
        tokenIn: tokenIn,
        tokenOut: tokenOut,
        fee: poolFee,
        recipient: msg.sender,
        deadline: block.timestamp,
        amountIn: inAmount,
        amountOutMinimum: outAmountMin,
        sqrtPriceLimitX96: 0
      })
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
    IUniswapV3Pool _pool = IUniswapV3Pool(_poolAddy);
    token0 = _pool.token0();
    token1 = _pool.token1();
    uint8 token0Decimals = ERC20(token0).decimals();
    uint8 token1Decimals = ERC20(token1).decimals();
    (uint160 sqrtPriceX96, , , , , , ) = _pool.slot0();
    priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);

    priceUSDNoDecimalsX128 = _getPriceUSDOfTargetTokenNoDecimalsX128(
      _targetToken,
      priceX96,
      token0,
      token0Decimals,
      token1,
      token1Decimals
    );

    return (
      _pool.fee(),
      token0,
      token1,
      // NOTE: this is not actually representative of the real liquidity in a pool
      // as Uniswap V3 has fragmented liquidity. To get real reserves and price impact
      // based on nonexecuted swaps check QuoterV2:
      // https://docs.uniswap.org/contracts/v3/reference/periphery/lens/QuoterV2
      ERC20(token0).balanceOf(address(_pool)),
      ERC20(token1).balanceOf(address(_pool)),
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
    IUniswapV3Pool _pool = IUniswapV3Pool(WETH9_STABLE_POOL);
    address token0 = _pool.token0();
    address token1 = _pool.token1();
    uint8 token0Decimals = ERC20(token0).decimals();
    uint8 token1Decimals = ERC20(token1).decimals();
    (uint160 sqrtPriceX96, , , , , , ) = _pool.slot0();
    uint256 priceX96 = FullMath.mulDiv(
      sqrtPriceX96,
      sqrtPriceX96,
      FixedPoint96.Q96
    );

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

