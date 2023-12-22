// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ITimeswapV2PeripheryCloseLendGivenPosition} from "./ITimeswapV2PeripheryCloseLendGivenPosition.sol";

import {INativeWithdraws} from "./INativeWithdraws.sol";
import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryUniswapV3CloseLendGivenPositionParam} from "./structs_Param.sol";

import {IUniswapImmutableState} from "./IUniswapImmutableState.sol";

/// @title An interface for TS-V2 Periphery UniswapV3 Close Lend Given Position.
interface ITimeswapV2PeripheryUniswapV3CloseLendGivenPosition is
  ITimeswapV2PeripheryCloseLendGivenPosition,
  IUniswapImmutableState,
  IUniswapV3SwapCallback,
  INativeWithdraws,
  IMulticall
{
  event CloseLendGivenPosition(
    address indexed token0,
    address indexed token1,
    uint256 strike,
    uint256 indexed maturity,
    uint24 uniswapV3Fee,
    address from,
    address to,
    bool isToken0,
    uint256 tokenAmount,
    uint256 positionAmount
  );

  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The close lend given position function.
  /// @param param Close lend given position param.
  /// @return tokenAmount
  function closeLendGivenPosition(
    TimeswapV2PeripheryUniswapV3CloseLendGivenPositionParam calldata param
  ) external returns (uint256 tokenAmount);
}

