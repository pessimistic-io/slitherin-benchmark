// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryNoDexQuoterAddLiquidityGivenPrincipalParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";

interface ITimeswapV2PeripheryNoDexQuoterAddLiquidityGivenPrincipal is
  ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal,
  IMulticall
{
  /// @dev Initializes the contract.
  /// @dev Calls the initialize in the pool.
  function initialize(address token0, address token1, uint256 strike, uint256 maturity, uint160 rate) external;

  /// @dev The add liquidity function.
  /// @param param Add liquidity param.
  /// @return liquidityAmount
  /// @return excessLongAmount
  /// @return excessShortAmount
  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryNoDexQuoterAddLiquidityGivenPrincipalParam calldata param,
    uint96 durationForward
  )
    external
    returns (
      uint160 liquidityAmount,
      uint256 excessLongAmount,
      uint256 excessShortAmount,
      uint160 timeswapV2LiquidityAfter
    );
}

