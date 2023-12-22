// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Error} from "./Error.sol";

import {StrikeConversion} from "./StrikeConversion.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryWithdraw} from "./TimeswapV2PeripheryWithdraw.sol";

import {TimeswapV2PeripheryWithdrawParam} from "./contracts_structs_Param.sol";

import {ITimeswapV2PeripheryNoDexWithdraw} from "./ITimeswapV2PeripheryNoDexWithdraw.sol";

import {TimeswapV2PeripheryNoDexWithdrawParam} from "./structs_Param.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {NativeImmutableState, NativeWithdraws} from "./Native.sol";
import {Multicall} from "./Multicall.sol";

/// @title Capable of withdrawing position from Timeswap V2 Protocol
/// @author Timeswap Labs
contract TimeswapV2PeripheryNoDexWithdraw is
  TimeswapV2PeripheryWithdraw,
  ITimeswapV2PeripheryNoDexWithdraw,
  OnlyOperatorReceiver,
  NativeImmutableState,
  NativeWithdraws,
  Multicall
{
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenTokens,
    address chosenNative
  ) TimeswapV2PeripheryWithdraw(chosenOptionFactory, chosenTokens) NativeImmutableState(chosenNative) {}

  /// @inheritdoc ITimeswapV2PeripheryNoDexWithdraw
  function withdraw(
    TimeswapV2PeripheryNoDexWithdrawParam calldata param
  ) external override returns (uint256 token0Amount, uint256 token1Amount) {
    if (param.deadline < block.timestamp) Error.deadlineReached(param.deadline);

    ITimeswapV2Token(tokens).transferTokenPositionFrom(
      msg.sender,
      address(this),
      TimeswapV2TokenPosition({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        position: TimeswapV2OptionPosition.Short
      }),
      param.positionAmount
    );

    (token0Amount, token1Amount) = withdraw(
      TimeswapV2PeripheryWithdrawParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.to,
        token1To: param.to,
        positionAmount: param.positionAmount
      })
    );

    if (token0Amount < param.minToken0Amount) revert MinTokenReached(token0Amount, param.minToken0Amount);
    if (token1Amount < param.minToken1Amount) revert MinTokenReached(token1Amount, param.minToken1Amount);

    emit Withdraw(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      param.to,
      token0Amount,
      token1Amount,
      param.positionAmount
    );
  }
}

