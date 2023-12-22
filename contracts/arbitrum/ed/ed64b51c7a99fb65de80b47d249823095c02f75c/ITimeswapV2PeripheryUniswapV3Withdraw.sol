// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ITimeswapV2PeripheryWithdraw} from "./ITimeswapV2PeripheryWithdraw.sol";

import {INativeWithdraws} from "./INativeWithdraws.sol";
import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryUniswapV3WithdrawParam} from "./structs_Param.sol";

import {IUniswapImmutableState} from "./IUniswapImmutableState.sol";

/// @title An interface for TS-V2 Periphery UniswapV3 Withdraw.
interface ITimeswapV2PeripheryUniswapV3Withdraw is
  ITimeswapV2PeripheryWithdraw,
  IUniswapImmutableState,
  IUniswapV3SwapCallback,
  INativeWithdraws,
  IMulticall
{
  event Withdraw(
    address indexed token0,
    address indexed token1,
    uint256 strike,
    uint256 indexed maturity,
    uint24 uniswapV3Fee,
    address to,
    bool isToken0,
    uint256 tokenAmount,
    uint256 positionAmount
  );

  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The withdraw function.
  /// @param param Withdraw param.
  /// @return tokenAmount
  function withdraw(TimeswapV2PeripheryUniswapV3WithdrawParam calldata param) external returns (uint256 tokenAmount);
}

