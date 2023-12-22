// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {ITimeswapV2PeripheryQuoterWithdraw} from "./ITimeswapV2PeripheryQuoterWithdraw.sol";

import {TimeswapV2PeripheryUniswapV3QuoterWithdrawParam} from "./QuoterParam.sol";

import {IMulticall} from "./IMulticall.sol";
import {IUniswapImmutableState} from "./IUniswapImmutableState.sol";

/// @title An interface for TS-V2 Periphery UniswapV3 Withdraw.
interface ITimeswapV2PeripheryUniswapV3QuoterWithdraw is
  ITimeswapV2PeripheryQuoterWithdraw,
  IUniswapImmutableState,
  IUniswapV3SwapCallback,
  IMulticall
{
  error MinTokenReached(uint256 tokenAmount, uint256 minTokenAmount);

  /// @dev The withdraw function.
  /// @param param Withdraw param.
  /// @return tokenAmount
  function withdraw(
    TimeswapV2PeripheryUniswapV3QuoterWithdrawParam calldata param
  ) external returns (uint256 tokenAmount, uint160 uniswapV3SqrtPriceAfter);
}

