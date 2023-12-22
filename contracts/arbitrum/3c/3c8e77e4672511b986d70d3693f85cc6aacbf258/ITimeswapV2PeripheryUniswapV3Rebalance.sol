// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ITimeswapV2PeripheryRebalance} from "./ITimeswapV2PeripheryRebalance.sol";

import {TimeswapV2PeripheryUniswapV3RebalanceParam} from "./structs_Param.sol";
import {INativeWithdraws} from "./INativeWithdraws.sol";
import {IMulticall} from "./IMulticall.sol";

import {IUniswapImmutableState} from "./IUniswapImmutableState.sol";

/// @title An interface for TS-V2 Periphery UniswapV3 Rebalance.
interface ITimeswapV2PeripheryUniswapV3Rebalance is
  ITimeswapV2PeripheryRebalance,
  IUniswapImmutableState,
  IUniswapV3SwapCallback,
  INativeWithdraws,
  IMulticall
{
  event Rebalance(
    address indexed token0,
    address indexed token1,
    uint256 strike,
    uint256 indexed maturity,
    uint24 uniswapV3Fee,
    address from,
    address tokenTo,
    address excessShortTo,
    bool isToken0,
    uint256 tokenAmount,
    uint256 excessShortAmount
  );

  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  error MinExcessShortReached(uint256 excessShortAmount, uint256 minExcessShortAmount);

  error NoRebalanceProfit();

  /// @dev The rebalance function.
  /// @param param Rebalance param.
  /// @return tokenAmount
  /// @return excessShortAmount
  function rebalance(
    TimeswapV2PeripheryUniswapV3RebalanceParam calldata param
  ) external returns (uint256 tokenAmount, uint256 excessShortAmount);
}

