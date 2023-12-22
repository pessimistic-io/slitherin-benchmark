// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2OptionCollectCallback} from "./ITimeswapV2OptionCollectCallback.sol";

/// @title An interface for TS-V2 Periphery Short Breakdown
interface ITimeswapV2PeripheryQuoterShortAfterMaturity is ITimeswapV2OptionCollectCallback {
  error PassOptionCollectCallbackInfo(uint256 token0Amount, uint256 token1Amount);

  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external returns (address);
}

