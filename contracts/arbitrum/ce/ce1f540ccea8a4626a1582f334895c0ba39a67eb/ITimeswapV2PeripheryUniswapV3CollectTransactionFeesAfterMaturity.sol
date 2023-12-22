// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity} from "./ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity.sol";

import {INativeWithdraws} from "./INativeWithdraws.sol";
import {IMulticall} from "./IMulticall.sol";

import {TimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturityParam} from "./structs_Param.sol";

import {IUniswapImmutableState} from "./IUniswapImmutableState.sol";

/// @title An interface for TS-V2 Periphery UniswapV3 Collect Transaction Fees.
interface ITimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturity is
  ITimeswapV2PeripheryCollectTransactionFeesAfterMaturity,
  IUniswapImmutableState,
  IUniswapV3SwapCallback,
  INativeWithdraws,
  IMulticall
{
  event CollectTransactionFeesAfterMaturity(
    address indexed token0,
    address indexed token1,
    uint256 strike,
    uint256 indexed maturity,
    uint24 uniswapV3Fee,
    address from,
    address to,
    bool isToken0,
    uint256 tokenAmount
  );

  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The collect transaction fees function.
  /// @param param Collect transaction fees param.
  /// @return tokenAmount
  function collectTransactionFeesAfterMaturity(
    TimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturityParam calldata param
  ) external returns (uint256 tokenAmount);
}

