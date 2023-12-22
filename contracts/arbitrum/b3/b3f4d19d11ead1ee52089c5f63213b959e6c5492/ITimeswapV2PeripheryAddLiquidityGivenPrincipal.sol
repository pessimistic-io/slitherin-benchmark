// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2OptionMintCallback} from "./ITimeswapV2OptionMintCallback.sol";

import {ITimeswapV2PoolMintCallback} from "./ITimeswapV2PoolMintCallback.sol";
import {ITimeswapV2PoolAddFeesCallback} from "./ITimeswapV2PoolAddFeesCallback.sol";

import {ITimeswapV2LiquidityTokenMintCallback} from "./ITimeswapV2LiquidityTokenMintCallback.sol";
import {ITimeswapV2LiquidityTokenAddFeesCallback} from "./ITimeswapV2LiquidityTokenAddFeesCallback.sol";

interface ITimeswapV2PeripheryAddLiquidityGivenPrincipal is
  ITimeswapV2OptionMintCallback,
  ITimeswapV2PoolMintCallback,
  ITimeswapV2PoolAddFeesCallback,
  ITimeswapV2LiquidityTokenMintCallback,
  ITimeswapV2LiquidityTokenAddFeesCallback
{
  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);

  /// @dev Returns the pool factory address.
  /// @return poolFactory The pool factory address.
  function poolFactory() external returns (address);

  /// @dev Return the liquidity tokens address
  function liquidityTokens() external returns (address);
}

