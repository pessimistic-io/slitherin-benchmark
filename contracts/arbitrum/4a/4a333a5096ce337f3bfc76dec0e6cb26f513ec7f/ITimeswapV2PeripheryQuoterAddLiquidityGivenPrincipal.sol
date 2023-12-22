// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2OptionMintCallback} from "./ITimeswapV2OptionMintCallback.sol";

import {ITimeswapV2PoolMintCallback} from "./ITimeswapV2PoolMintCallback.sol";

interface ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal is
  ITimeswapV2OptionMintCallback,
  ITimeswapV2PoolMintCallback
{
  error PassOptionMintCallbackInfo(uint256 shortAmountMinted, bytes data);

  error PassPoolMintCallbackInfo(
    uint160 liquidityAmount,
    uint256 long0ExcessAmount,
    uint256 long1ExcessAmount,
    uint256 shortExcessAmount,
    uint160 timeswapV2LiquidityAfter,
    bytes data
  );

  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);

  /// @dev Returns the pool factory address.
  /// @return poolFactory The pool factory address.
  function poolFactory() external returns (address);

  /// @dev Return the liquidity tokens address
  function liquidityTokens() external returns (address);
}

