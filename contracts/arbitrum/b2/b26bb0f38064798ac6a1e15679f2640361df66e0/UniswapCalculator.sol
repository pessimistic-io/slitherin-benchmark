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
}

