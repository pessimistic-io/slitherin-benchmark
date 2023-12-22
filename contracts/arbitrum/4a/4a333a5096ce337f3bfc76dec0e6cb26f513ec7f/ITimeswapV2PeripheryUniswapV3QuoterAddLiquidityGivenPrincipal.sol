// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipalParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";
import {IUniswapImmutableState} from "./IUniswapImmutableState.sol";

interface ITimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipal is
  ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal,
  IUniswapImmutableState,
  IUniswapV3SwapCallback,
  IMulticall
{
  /// @dev Initializes the contract.
  /// @dev Calls the initialize in the pool.
  function initialize(address token0, address token1, uint256 strike, uint256 maturity, uint160 rate) external;

  /// @dev The add liquidity function.
  /// @param param Add liquidity param.
  /// @return liquidityAmount
  /// @return excessLong0Amount
  /// @return excessLong1Amount
  /// @return excessShortAmount
  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipalParam calldata param,
    uint96 durationForward
  )
    external
    returns (
      uint160 liquidityAmount,
      uint256 excessLong0Amount,
      uint256 excessLong1Amount,
      uint256 excessShortAmount,
      uint160 timeswapV2LiquidityAfter,
      uint160 uniswapV3SqrtPriceAfter
    );
}

