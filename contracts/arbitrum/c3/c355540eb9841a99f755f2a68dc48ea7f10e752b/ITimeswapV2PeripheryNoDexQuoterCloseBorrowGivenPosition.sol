// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterCloseBorrowGivenPosition} from "./ITimeswapV2PeripheryQuoterCloseBorrowGivenPosition.sol";

import {TimeswapV2PeripheryNoDexQuoterCloseBorrowGivenPositionParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";

/// @title An interface for TS-v2 Periphery NoDex Close Borrow Given Position.
interface ITimeswapV2PeripheryNoDexQuoterCloseBorrowGivenPosition is
  ITimeswapV2PeripheryQuoterCloseBorrowGivenPosition,
  IMulticall
{
  /// @dev The close borrow given position function.
  /// @param param Close borrow given position param.
  /// @return tokenAmount
  function closeBorrowGivenPosition(
    TimeswapV2PeripheryNoDexQuoterCloseBorrowGivenPositionParam calldata param,
    uint96 durationForward
  ) external returns (uint256 tokenAmount, uint160 timeswapV2SqrtInterestRateAfter);
}

