// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterCollect} from "./ITimeswapV2PeripheryQuoterCollect.sol";

import {TimeswapV2PeripheryNoDexQuoterCollectParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";

/// @title An interface for TS-V2 Periphery NoDex Collect.
interface ITimeswapV2PeripheryNoDexQuoterCollect is ITimeswapV2PeripheryQuoterCollect, IMulticall {
  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The collect function.
  /// @param param collect param.
  /// @return token0Amount
  /// @return token1Amount
  function collect(
    TimeswapV2PeripheryNoDexQuoterCollectParam calldata param
  ) external returns (uint256 token0Amount, uint256 token1Amount);
}

