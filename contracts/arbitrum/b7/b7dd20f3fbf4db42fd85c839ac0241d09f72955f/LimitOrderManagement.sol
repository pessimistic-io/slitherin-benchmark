// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import "./IAlgebraPoolErrors.sol";
import "./FullMath.sol";
import "./Constants.sol";

/// @title LimitOrderManagement
/// @notice Contains functions for managing limit orders and relevant calculations
library LimitOrderManagement {
  struct LimitOrder {
    uint128 amountToSell;
    uint128 soldAmount;
    uint256 boughtAmount0Cumulative;
    uint256 boughtAmount1Cumulative;
    bool initialized;
  }

  /// @notice Updates a limit order state and returns true if the tick was flipped from initialized to uninitialized, or vice versa
  /// @param self The mapping containing limit order cumulatives for initialized ticks
  /// @param tick The tick that will be updated
  /// @param amount The amount of liquidity that will be added/removed
  /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
  function addOrRemoveLimitOrder(mapping(int24 => LimitOrder) storage self, int24 tick, int128 amount) internal returns (bool flipped) {
    LimitOrder storage data = self[tick];
    uint128 _amountToSell = data.amountToSell;
    unchecked {
      if (amount > 0) {
        flipped = _amountToSell == 0;
        _amountToSell += uint128(amount);
      } else {
        _amountToSell -= uint128(-amount);
        flipped = _amountToSell == 0;
        if (flipped) data.soldAmount = 0; // reset filled amount if all orders are closed
      }
      data.amountToSell = _amountToSell;
    }
  }

  /// @notice Adds/removes liquidity to tick with partly executed limit order
  /// @param self The mapping containing limit order cumulatives for initialized ticks
  /// @param tick The tick that will be updated
  /// @param amount The amount of liquidity that will be added/removed
  function addVirtualLiquidity(mapping(int24 => LimitOrder) storage self, int24 tick, int128 amount) internal {
    LimitOrder storage data = self[tick];
    if (amount > 0) {
      data.amountToSell += uint128(amount);
      data.soldAmount += uint128(amount);
    } else {
      data.amountToSell -= uint128(-amount);
      data.soldAmount -= uint128(-amount);
    }
  }

  /// @notice Executes a limit order on the specified tick
  /// @param self The mapping containing limit order cumulatives for initialized ticks
  /// @param tick Limit order execution tick
  /// @param tickSqrtPrice Limit order execution price
  /// @param zeroToOne The direction of the swap, true for token0 to token1, false for token1 to token0
  /// @param amountA Amount of tokens that will be swapped
  /// @param fee The fee taken from the input amount, expressed in hundredths of a bip
  /// @return closed Status of limit order after execution
  /// @return amountOut Amount of token that user receive after swap
  /// @return amountIn Amount of token that user need to pay
  function executeLimitOrders(
    mapping(int24 => LimitOrder) storage self,
    int24 tick,
    uint160 tickSqrtPrice,
    bool zeroToOne,
    int256 amountA,
    uint16 fee
  ) internal returns (bool closed, uint256 amountOut, uint256 amountIn, uint256 feeAmount) {
    unchecked {
      bool exactIn = amountA > 0;
      if (!exactIn) amountA = -amountA;
      if (amountA < 0) revert IAlgebraPoolErrors.invalidAmountRequired(); // in case of type(int256).min

      // price is defined as "token1/token0"
      uint256 price = FullMath.mulDiv(tickSqrtPrice, tickSqrtPrice, Constants.Q96);

      uint256 amountB = (zeroToOne == exactIn)
        ? FullMath.mulDiv(uint256(amountA), price, Constants.Q96) // tokenA is token0
        : FullMath.mulDiv(uint256(amountA), Constants.Q96, price); // tokenA is token1

      // limit orders buy tokenIn and sell tokenOut
      (amountOut, amountIn) = exactIn ? (amountB, uint256(amountA)) : (uint256(amountA), amountB);

      LimitOrder storage data = self[tick];
      (uint128 amountToSell, uint128 soldAmount) = (data.amountToSell, data.soldAmount);
      uint256 unsoldAmount = amountToSell - soldAmount; // safe since soldAmount always < amountToSell

      if (exactIn) {
        amountOut = FullMath.mulDiv(amountOut, Constants.FEE_DENOMINATOR - fee, Constants.FEE_DENOMINATOR);
      }

      if (amountOut >= unsoldAmount) {
        if (amountOut > unsoldAmount) {
          amountOut = unsoldAmount;
        }
        (closed, data.amountToSell, data.soldAmount) = (true, 0, 0);
      } else {
        // overflow is desired since we do not support tokens with totalSupply > type(uint128).max
        data.soldAmount = soldAmount + uint128(amountOut);
      }

      amountIn = zeroToOne ? FullMath.mulDivRoundingUp(amountOut, Constants.Q96, price) : FullMath.mulDivRoundingUp(amountOut, price, Constants.Q96);
      if (exactIn) {
        if (amountOut == unsoldAmount) {
          feeAmount = FullMath.mulDivRoundingUp(amountIn, fee, Constants.FEE_DENOMINATOR);
        } else {
          feeAmount = uint256(amountA) - amountIn;
        }
      } else {
        feeAmount = FullMath.mulDivRoundingUp(amountIn, fee, Constants.FEE_DENOMINATOR - fee);
      }

      // overflows are desired since there are relative accumulators
      if (zeroToOne) {
        data.boughtAmount0Cumulative += FullMath.mulDiv(amountIn, Constants.Q128, amountToSell);
      } else {
        data.boughtAmount1Cumulative += FullMath.mulDiv(amountIn, Constants.Q128, amountToSell);
      }
    }
  }
}

