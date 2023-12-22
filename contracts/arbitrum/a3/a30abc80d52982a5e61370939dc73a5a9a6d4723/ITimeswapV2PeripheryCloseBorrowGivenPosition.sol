// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC1155Receiver} from "./IERC1155Receiver.sol";

import {ITimeswapV2OptionSwapCallback} from "./ITimeswapV2OptionSwapCallback.sol";

import {ITimeswapV2PoolDeleverageCallback} from "./ITimeswapV2PoolDeleverageCallback.sol";

/// @title An interface for TS-V2 Periphery Close Borrow Given Position
interface ITimeswapV2PeripheryCloseBorrowGivenPosition is
  ITimeswapV2OptionSwapCallback,
  ITimeswapV2PoolDeleverageCallback,
  IERC1155Receiver
{
  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);

  /// @dev Returns the pool factory address.
  /// @return poolFactory The pool factory address.
  function poolFactory() external returns (address);

  /// @dev Return the tokens address
  function tokens() external returns (address);
}

