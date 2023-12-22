// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition} from "./ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition.sol";
import {FeesAndReturnedDelta, ExcessDelta} from "./structs_Param.sol";

import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPositionParam} from "./QuoterParam.sol";

/// @title An interface for TS-V2 Periphery NoDex RemoveLiquidity Quoter.
interface ITimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPosition is
  ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition,
  IMulticall
{
  /// @dev The remove liquidity function.
  /// @param param Remove liquidity param.
  /// @param durationForward The time moved forward for quotation.
  /// @return token0Amount
  /// @return token1Amount
  /// @return feesAndReturnedDelta
  /// @return excessDelta
  /// @return timeswapV2LiquidityAfter
  function removeLiquidityGivenPosition(
    TimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPositionParam calldata param,
    uint96 durationForward
  )
    external
    returns (
      uint256 token0Amount,
      uint256 token1Amount,
      FeesAndReturnedDelta memory feesAndReturnedDelta,
      ExcessDelta memory excessDelta,
      uint160 timeswapV2LiquidityAfter
    );
}

