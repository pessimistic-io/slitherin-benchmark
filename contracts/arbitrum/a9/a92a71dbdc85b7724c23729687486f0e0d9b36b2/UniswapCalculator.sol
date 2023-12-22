// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import "./FullMath.sol";
import "./TickMath.sol";
import "./LiquidityAmounts.sol";
import "./IUniswapV3Pool.sol";
import "./IStrategyRebalanceStakerUniV3.sol";
import "./erc20.sol";

/**
 * This contract is for calculating liquidity and amounts for a given set of prices.
 */
contract UniswapCalculator {
  /**
   * @dev Returns the square root ratio at a given tick.
   * @param _tick The tick value to get the square root ratio for.
   * @return The square root ratio at the given tick.
   */
  function getSqrtRatioAtTick(int24 _tick) external view returns (uint160) {
    return TickMath.getSqrtRatioAtTick(_tick);
  }

  /**
   * @dev Returns the liquidity required to buy a given amount of asset 0.
   * @param sqrtRatioAX96 The square root ratio for asset 0.
   * @param sqrtRatioBX96 The square root ratio for asset 1.
   * @param amount0 The amount of asset 0 to buy.
   * @return The required liquidity.
   */
  function getLiquidityForAmount0(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint256 amount0
  ) external pure returns (uint128) {
    return LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
  }

  /**
   * @dev Returns the liquidity required to buy a given amount of asset 1.
   * @param sqrtRatioAX96 The square root ratio for asset 0.
   * @param sqrtRatioBX96 The square root ratio for asset 1.
   * @param amount1 The amount of asset 1 to buy.
   * @return The required liquidity.
   */
  function getLiquidityForAmount1(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint256 amount1
  ) external pure returns (uint128) {
    return LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
  }

  /**
   * @dev Returns the amounts that can be bought with a given liquidity.
   * @param sqrtRatioX96 The square root ratio for the price pool.
   * @param sqrtRatioAX96 The square root ratio for asset 0.
   * @param sqrtRatioBX96 The square root ratio for asset 1.
   * @param liquidity The amount of liquidity to use.
   * @return  amount0 The amounts of assets that can be bought for amount0.
   * @return  amount1 The amounts of assets that can be bought for amount1.
   */
  function getAmountsForLiquidity(
    uint160 sqrtRatioX96,
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint128 liquidity
  ) external pure returns (uint256 amount0, uint256 amount1) {
    return LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
  }

  /**
   * @dev Returns the liquidity required to buy given amounts of assets.
   * @param sqrtRatioX96 The square root ratio for the price pool.
   * @param sqrtRatioAX96 The square root ratio for asset 0.
   * @param sqrtRatioBX96 The square root ratio for asset 1.
   * @param amount0 The amount of asset 0 to buy.
   * @param amount1 The amount of asset 1 to buy.
   * @return The required liquidity.
   */
  function getLiquidityForAmounts(
    uint160 sqrtRatioX96,
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint256 amount0,
    uint256 amount1
  ) external pure returns (uint128) {
    return LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
  }

  /**
   * @dev Returns the liquidity required to buy given amounts of assets with prices
   *      between tickLower and tickUpper.
   * @param sqrtRatioX96 The square root ratio for the price pool.
   * @param amount0 The amount of asset 0 to buy.
   * @param amount1 The amount of asset 1 to buy.
   * @param _tickLower The lower tick value to use for price calculation.
   * @param _tickUpper The upper tick value to use for price calculation.
   * @return The required liquidity.
   */
  function liquidityForAmounts(
    uint160 sqrtRatioX96,
    uint256 amount0,
    uint256 amount1,
    int24 _tickLower,
    int24 _tickUpper
  ) external view returns (uint128) {
    //Get current price from the pool

    return
      LiquidityAmounts.getLiquidityForAmounts(
        sqrtRatioX96,
        TickMath.getSqrtRatioAtTick(_tickLower),
        TickMath.getSqrtRatioAtTick(_tickUpper),
        amount0,
        amount1
      );
  }

  /**
   * @dev Returns the amounts that can be bought with a given liquidity and
   *      prices between tickLower and tickUpper.
   * @param sqrtRatioX96 The square root ratio for the price pool.
   * @param liquidity The amount of liquidity to use.
   * @param _tickLower The lower tick value to use for price calculation.
   * @param _tickUpper The upper tick value to use for price calculation.
   * @return The amounts of assets that can be bought.
   */
  function amountsForLiquidity(
    uint160 sqrtRatioX96,
    uint128 liquidity,
    int24 _tickLower,
    int24 _tickUpper
  ) external view returns (uint256, uint256) {
    //Get current price from the pool
    return
      LiquidityAmounts.getAmountsForLiquidity(
        sqrtRatioX96,
        TickMath.getSqrtRatioAtTick(_tickLower),
        TickMath.getSqrtRatioAtTick(_tickUpper),
        liquidity
      );
  }

  /**
   * @dev Returns the lower and upper tick values for a given set of inputs.
   * @param _cumulativeTicks The cumulative tick values to use for tick calculation.
   * @param _tickSpacing The tick spacing value to use.
   * @param _tickRangeMultiplier The tick range multiplier value to use.
   * @param _twapTime The time window to use for tick calculation.
   * @return The lower and upper tick values for the given inputs.
   */
  function determineTicksCalc(
    int56[] memory _cumulativeTicks,
    int24 _tickSpacing,
    int24 _tickRangeMultiplier,
    uint24 _twapTime
  ) external view returns (int24, int24) {
    int56 _averageTick = (_cumulativeTicks[1] - _cumulativeTicks[0]) / _twapTime;
    int24 baseThreshold = _tickSpacing * _tickRangeMultiplier;
    return _baseTicks(int24(_averageTick), baseThreshold, _tickSpacing);
  }

  /**
   * @dev Internal function that returns the greatest multiple of tickSpacing less
   *      than or equal to tick.
   * @param _tick The tick value to floor.
   * @param _tickSpacing The tick spacing value to use.
   * @return The floored tick value.
   */
  function _floor(int24 _tick, int24 _tickSpacing) internal pure returns (int24) {
    int24 compressed = _tick / _tickSpacing;
    if (_tick < 0 && _tick % _tickSpacing != 0) compressed--;
    return compressed * _tickSpacing;
  }

  /**
   * @dev Internal function that returns the tick values based on the given inputs.
   * @param _currentTick The tick value to base the calculations on.
   * @param _baseThreshold The base threshold value to use.
   * @param _tickSpacing The tick spacing value to use.
   * @return  tickLower  The lower tick values.
   * @return  tickUpper  The upper tick values.
   */
  function _baseTicks(
    int24 _currentTick,
    int24 _baseThreshold,
    int24 _tickSpacing
  ) internal pure returns (int24 tickLower, int24 tickUpper) {
    int24 tickFloor = _floor(_currentTick, _tickSpacing);

    tickLower = tickFloor - _baseThreshold;
    tickUpper = tickFloor + _baseThreshold;
  }

  /**
   * @notice  Calculates balances of assets
   * @dev     Calcuates how much token0 / token1 exists in the contract
   * @param   _dysonStrategy  Strategy to check
   * @return  _a0Expect  amount in token0 that is to be expected
   * @return  _a1Expect  amount in token1 that is to be expected
   */
  function getLiquidity(IStrategyRebalanceStakerUniV3 _dysonStrategy)
    public
    view
    returns (uint256 _a0Expect, uint256 _a1Expect)
  {
    IUniswapV3Pool _pool = IUniswapV3Pool(_dysonStrategy.pool());

    int24 _tickLower = _dysonStrategy.tick_lower();
    int24 _tickUpper = _dysonStrategy.tick_upper();
    uint256 _liquidity = _dysonStrategy.liquidityOfPool();
    (_a0Expect, _a1Expect) = amountsForLiquidity(_pool, uint128(_liquidity), _tickLower, _tickUpper);
    _a0Expect += (IERC20(address(_pool.token0())).balanceOf(address(_dysonStrategy)));
    _a1Expect += (IERC20(address(_pool.token1())).balanceOf(address(_dysonStrategy)));
  }

  /// @dev Wrapper around `LiquidityAmounts.getAmountsForLiquidity()`.
  /// @param pool Uniswap V3 pool
  /// @param liquidity  The liquidity being valued
  /// @param _tickLower The lower tick of the range
  /// @param _tickUpper The upper tick of the range
  /// @return amounts of token0 and token1 that corresponds to liquidity
  function amountsForLiquidity(
    IUniswapV3Pool pool,
    uint128 liquidity,
    int24 _tickLower,
    int24 _tickUpper
  ) internal view returns (uint256, uint256) {
    //Get current price from the pool
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    return
      LiquidityAmounts.getAmountsForLiquidity(
        sqrtRatioX96,
        TickMath.getSqrtRatioAtTick(_tickLower),
        TickMath.getSqrtRatioAtTick(_tickUpper),
        liquidity
      );
  }

  /**
   * @dev get price from tick
   */
  function getSqrtRatio(int24 tick) public pure returns (uint160) {
    return TickMath.getSqrtRatioAtTick(tick);
  }

  /**
   * @dev get tick from price
   */
  function getTickFromPrice(uint160 price) public pure returns (int24) {
    return TickMath.getTickAtSqrtRatio(price);
  }
}

