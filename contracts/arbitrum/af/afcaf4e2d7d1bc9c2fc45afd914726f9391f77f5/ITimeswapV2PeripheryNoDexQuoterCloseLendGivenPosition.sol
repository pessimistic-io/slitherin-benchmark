// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterCloseLendGivenPosition} from "./ITimeswapV2PeripheryQuoterCloseLendGivenPosition.sol";

import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryNoDexQuoterCloseLendGivenPositionParam} from "./QuoterParam.sol";

/// @title An interface for TS-V2 Periphery NoDex Close Lend Given Position.
interface ITimeswapV2PeripheryNoDexQuoterCloseLendGivenPosition is
  ITimeswapV2PeripheryQuoterCloseLendGivenPosition,
  IMulticall
{
  /// @dev The close lend given position function.
  /// @param param Close lend given position param.
  /// @return token0Amount
  /// @return token1Amount
  /// @return timeswapV2SqrtInterestRateAfter

  function closeLendGivenPosition(
    TimeswapV2PeripheryNoDexQuoterCloseLendGivenPositionParam calldata param,
    uint96 durationForward
  ) external returns (uint256 token0Amount, uint256 token1Amount, uint160 timeswapV2SqrtInterestRateAfter);
}

