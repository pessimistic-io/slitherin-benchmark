// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC1155Receiver} from "./IERC1155Receiver.sol";

import {ITimeswapV2TokenBurnCallback} from "./ITimeswapV2TokenBurnCallback.sol";

/// @title An interface for TS-V2 Periphery Withdraw
interface ITimeswapV2PeripheryQuoterWithdraw is IERC1155Receiver, ITimeswapV2TokenBurnCallback {
  error PassTokenBurnCallbackInfo(uint256 token0Amount, uint256 token1Amount);

  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);

  /// @dev Return the tokens address
  function tokens() external returns (address);
}

