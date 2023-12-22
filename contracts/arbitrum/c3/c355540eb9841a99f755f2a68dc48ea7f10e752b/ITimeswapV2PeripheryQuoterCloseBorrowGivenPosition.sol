// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC1155Receiver} from "./IERC1155Receiver.sol";

import {ITimeswapV2OptionSwapCallback} from "./ITimeswapV2OptionSwapCallback.sol";

import {ITimeswapV2PoolDeleverageCallback} from "./ITimeswapV2PoolDeleverageCallback.sol";

import {ITimeswapV2TokenBurnCallback} from "./ITimeswapV2TokenBurnCallback.sol";

/// @title An interface for TS-V2 Periphery Close Borrow Given Position
interface ITimeswapV2PeripheryQuoterCloseBorrowGivenPosition is
  ITimeswapV2OptionSwapCallback,
  ITimeswapV2PoolDeleverageCallback,
  ITimeswapV2TokenBurnCallback,
  IERC1155Receiver
{
  error PassTokenBurnCallbackInfo(
    uint160 timeswapV2SqrtInterestRateAfter,
    uint256 token0Amount,
    uint256 token1Amount,
    bytes data
  );

  error PassOptionSwapCallbackInfo(bytes data);

  error PassPoolDeleverageCallbackInfo(
    uint160 timeswapV2SqrtInterestRateAfter,
    uint256 token0Amount,
    uint256 token1Amount,
    bytes data
  );

  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);

  /// @dev Returns the pool factory address.
  /// @return poolFactory The pool factory address.
  function poolFactory() external returns (address);

  /// @dev Return the tokens address
  function tokens() external returns (address);
}

