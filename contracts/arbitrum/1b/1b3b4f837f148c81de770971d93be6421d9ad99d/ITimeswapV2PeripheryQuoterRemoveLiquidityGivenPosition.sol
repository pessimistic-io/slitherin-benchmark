// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {IERC1155Receiver} from "./IERC1155Receiver.sol";

import {ITimeswapV2OptionBurnCallback} from "./ITimeswapV2OptionBurnCallback.sol";

import {ITimeswapV2PoolBurnCallback} from "./ITimeswapV2PoolBurnCallback.sol";

import {ITimeswapV2TokenMintCallback} from "./ITimeswapV2TokenMintCallback.sol";

/// @title An interface for TS-V2 Periphery Remove Liquidity Given Position
interface ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition is
  ITimeswapV2OptionBurnCallback,
  ITimeswapV2PoolBurnCallback,
  ITimeswapV2TokenMintCallback,
  IERC1155Receiver
{
  error PassPoolBurnCallbackInfo(
    uint256 token0AmountFromPool,
    uint256 token1AmountFromPool,
    uint256 shortAmountFromPool,
    bytes data
  );

  error PassTokenMintCallbackInfo();

  error PassOptionBurnCallbackInfo(bytes data);

  /// @dev Returns the option factory address.
  function optionFactory() external returns (address);

  /// @dev Returns the pool factory address.
  function poolFactory() external returns (address);

  /// @dev Returns the tokens address.
  function tokens() external returns (address);

  /// @dev Returns the liquidity tokens address.
  function liquidityTokens() external returns (address);
}

