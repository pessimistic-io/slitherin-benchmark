// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ITimeswapV2PeripheryQuoterCloseLendGivenPosition} from "./ITimeswapV2PeripheryQuoterCloseLendGivenPosition.sol";

import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPositionParam} from "./QuoterParam.sol";

import {IUniswapImmutableState} from "./IUniswapImmutableState.sol";

/// @title An interface for TS-V2 Periphery UniswapV3 Close Lend Given Position.
interface ITimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPosition is
  ITimeswapV2PeripheryQuoterCloseLendGivenPosition,
  IUniswapImmutableState,
  IUniswapV3SwapCallback,
  IMulticall
{
  /// @dev The close lend given position function.
  /// @param param Close lend given position param.
  /// @return tokenAmount
  function closeLendGivenPosition(
    TimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPositionParam calldata param,
    uint96 durationForward
  ) external returns (uint256 tokenAmount, uint160 timeswapV2SqrtInterestRateAfter, uint160 uniswapV3SqrtPriceAfter);
}

