// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {ITimeswapV2PeripheryQuoterWithdraw} from "./ITimeswapV2PeripheryQuoterWithdraw.sol";

import {TimeswapV2PeripheryNoDexQuoterWithdrawParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";

/// @title An interface for TS-V2 Periphery NoDex Withdraw.
interface ITimeswapV2PeripheryNoDexQuoterWithdraw is ITimeswapV2PeripheryQuoterWithdraw, IMulticall {
  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The withdraw function.
  /// @param param Withdraw param.
  /// @return token0Amount
  /// @return token1Amount

  function withdraw(
    TimeswapV2PeripheryNoDexQuoterWithdrawParam calldata param
  ) external returns (uint256 token0Amount, uint256 token1Amount);
}

