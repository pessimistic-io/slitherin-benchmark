// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterShortAfterMaturity} from "./ITimeswapV2PeripheryQuoterShortAfterMaturity.sol";

import {TimeswapV2PeripheryNoDexQuoterShortAfterMaturityParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";

/// @title An interface for TS-V2 Periphery NoDex Short breakdown.
interface ITimeswapV2PeripheryNoDexQuoterShortAfterMaturity is
  ITimeswapV2PeripheryQuoterShortAfterMaturity,
  IMulticall
{
  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The withdraw function.
  /// @param param Withdraw param.
  /// @return token0Amount
  /// @return token1Amount
  function shortAfterMaturity(
    TimeswapV2PeripheryNoDexQuoterShortAfterMaturityParam calldata param
  ) external returns (uint256 token0Amount, uint256 token1Amount);
}

