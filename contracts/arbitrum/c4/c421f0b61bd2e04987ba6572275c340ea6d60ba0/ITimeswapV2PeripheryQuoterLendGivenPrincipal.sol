// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2OptionMintCallback} from "./ITimeswapV2OptionMintCallback.sol";

import {ITimeswapV2PoolDeleverageCallback} from "./ITimeswapV2PoolDeleverageCallback.sol";

import {ITimeswapV2TokenMintCallback} from "./ITimeswapV2TokenMintCallback.sol";

/// @title An interface for TS-V2 Periphery Lend Given Principal
interface ITimeswapV2PeripheryQuoterLendGivenPrincipal is
  ITimeswapV2OptionMintCallback,
  ITimeswapV2PoolDeleverageCallback,
  ITimeswapV2TokenMintCallback
{
  error PassOptionMintCallbackInfo(bytes data);

  error PassPoolDeleverageCallbackInfo(uint160 timeswapV2SqrtInterestRateAfter, bytes data);

  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);

  /// @dev Returns the pool factory address.
  /// @return poolFactory The pool factory address.
  function poolFactory() external returns (address);

  /// @dev Return the tokens address
  function tokens() external returns (address);
}

