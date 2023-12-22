// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { FullMath } from "./FullMath.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { TickMath } from "./TickMath.sol";
import { FixedPointMathLib } from "./FixedPointMathLib.sol";

library UniswapV3Zap {
  uint128 internal constant Q96 = 2 ** 96;
  uint256 internal constant Q192 = 2 ** 192;

  struct CalcParams {
    IUniswapV3Pool pool;
    uint256 amountIn0;
    uint256 amountIn1;
    int24 tickLower;
    int24 tickUpper;
  }

  /// @notice Calculate the amount of token0 or token1 to be swapped to add liquidity to the pool
  /// @dev This function is mainly developed for compounding the trading fees. Hence, amountIn0 and amountIn1
  /// are expected to be small enough to not cause the price to move significantly.
  /// @dev There will always be a dust left due to price move after swap. Hence, this dust should return to NFT's owner.
  function calc(
    CalcParams memory _params
  ) internal view returns (uint256 _swapAmount, bool _zeroForOne) {
    // Get pool states
    (uint160 _sqrtPriceX96, int24 _currentTick, , , , , ) = _params.pool.slot0();
    if (_currentTick >= _params.tickUpper) {
      // If current tick is greater than upper tick, then need to swap token0 to token1
      return (_params.amountIn0, true);
    }
    if (_currentTick <= _params.tickLower) {
      // If current tick is less than lower tick, then need to swap token1 to token0
      return (_params.amountIn1, false);
    }
    // tickLower and tickUpper is in the range of current tick.
    // Find out which token to swap and how much.
    (uint256 _expectedAmount0, uint256 _expectedAmount1) = LiquidityAmounts.getAmountsForLiquidity(
      _sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(_params.tickLower),
      TickMath.getSqrtRatioAtTick(_params.tickUpper),
      Q96
    );

    // Calculate the ratio of the expected ratio.
    uint256 _ratioX96 = FullMath.mulDiv(_expectedAmount0, Q96, _expectedAmount1);

    // Calculate the price of token0 and token1
    uint256 _amount1X96 = _ratioX96 * _params.amountIn1;
    uint256 _amount0X96 = _params.amountIn0 * Q96;

    // Get pool's fee
    uint24 _fee = _params.pool.fee();
    uint256 _priceX96 = 0;

    if (_amount1X96 < _amount0X96) {
      // Need to swap token0 to token1
      // Pool's fee handling below is for gas optimization
      // as most of the pool will fall into these 3 categories.
      if (_fee == 10000) {
        _sqrtPriceX96 = (99498743710 * _sqrtPriceX96) / 100000000000;
      } else if (_fee == 3000) {
        _sqrtPriceX96 = (99849887330 * _sqrtPriceX96) / 100000000000;
      } else if (_fee == 500) {
        _sqrtPriceX96 = (99974996874 * _sqrtPriceX96) / 100000000000;
      } else {
        // Handle if sqrt for fee is not hardcoded
        uint256 _base = FixedPointMathLib.sqrt(100000000000000 - uint256(_fee) * 100000000);
        _sqrtPriceX96 = (uint160(_base) * _sqrtPriceX96) / 10000000;
      }

      // Calculate the price as X96
      _priceX96 = FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, Q96);

      return (
        ((_amount0X96 - _amount1X96) / (FullMath.mulDiv(_ratioX96, _priceX96, Q96) + Q96)),
        true
      );
    }

    // Need to swap token1 to token0
    // Same as above.
    if (_fee == 10000) {
      _sqrtPriceX96 = (100498756211 * _sqrtPriceX96) / 100000000000;
    } else if (_fee == 3000) {
      _sqrtPriceX96 = (100149887668 * _sqrtPriceX96) / 100000000000;
    } else if (_fee == 500) {
      _sqrtPriceX96 = (100024996876 * _sqrtPriceX96) / 100000000000;
    } else {
      uint256 _base = FixedPointMathLib.sqrt(uint256(_fee) * 100000000 + 100000000000000);
      _sqrtPriceX96 = (uint160(_base) * _sqrtPriceX96) / 10000000;
    }

    // Calculate the price as X96
    _priceX96 = FullMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, Q96);

    return ((_amount1X96 - _amount0X96) / (_ratioX96 + (Q192 / _priceX96)), false);
  }
}
