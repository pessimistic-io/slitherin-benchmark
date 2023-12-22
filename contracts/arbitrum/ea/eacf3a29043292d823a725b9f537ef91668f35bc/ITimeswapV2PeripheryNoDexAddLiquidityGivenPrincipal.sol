// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryNoDexAddLiquidityGivenPrincipalParam} from "./structs_Param.sol";

import {INativePayments} from "./INativePayments.sol";
import {IMulticall} from "./IMulticall.sol";

/// @title An interface for TS-V2 Periphery No Dex Add Liquidity Given Principal.
interface ITimeswapV2PeripheryNoDexAddLiquidityGivenPrincipal is
  ITimeswapV2PeripheryAddLiquidityGivenPrincipal,
  INativePayments,
  IMulticall
{
  event AddLiquidityGivenPrincipal(
    address indexed token0,
    address indexed token1,
    uint256 strike,
    uint256 indexed maturity,
    address from,
    address liquidityTo,
    bool isToken0,
    uint256 tokenAmount,
    uint256 liquidityAmount,
    uint256 excessLongAmount,
    uint256 excessShortAmount
  );

  error MinLiquidityReached(uint160 liquidityAmount, uint160 minLiquidityAmount);

  error MinSqrtInterestRateReached(uint160 sqrtInterestRate, uint160 minSqrtInterestRate);

  error MaxSqrtInterestRateReached(uint160 sqrtInterestRate, uint160 maxSqrtInterestRate);

  /// @dev Initializes the contract.
  /// @dev Calls the initialize in the pool.
  function initialize(address token0, address token1, uint256 strike, uint256 maturity, uint160 rate) external;

  /// @dev The add liquidity function.
  /// @param param Add liquidity param.
  /// @return liquidityAmount
  /// @return excessLongAmount
  /// @return excessShortAmount
  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryNoDexAddLiquidityGivenPrincipalParam calldata param
  ) external payable returns (uint160 liquidityAmount, uint256 excessLongAmount, uint256 excessShortAmount);
}

