// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Error} from "./Error.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryWithdraw} from "./TimeswapV2PeripheryWithdraw.sol";

import {TimeswapV2PeripheryWithdrawParam} from "./contracts_structs_Param.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3SwapParam} from "./SwapParam.sol";

import {ITimeswapV2PeripheryUniswapV3Withdraw} from "./ITimeswapV2PeripheryUniswapV3Withdraw.sol";

import {TimeswapV2PeripheryUniswapV3WithdrawParam} from "./structs_Param.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {NativeImmutableState, NativeWithdraws} from "./Native.sol";
import {UniswapImmutableState, UniswapV3Callback} from "./UniswapV3SwapCallback.sol";
import {SwapGetTotalToken} from "./SwapCalculator.sol";
import {Multicall} from "./Multicall.sol";

/// @title Capable of withdrawing position from Timeswap V2 Protocol
/// @author Timeswap Labs
contract TimeswapV2PeripheryUniswapV3Withdraw is
  TimeswapV2PeripheryWithdraw,
  ITimeswapV2PeripheryUniswapV3Withdraw,
  OnlyOperatorReceiver,
  NativeImmutableState,
  NativeWithdraws,
  UniswapV3Callback,
  SwapGetTotalToken,
  Multicall
{
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenTokens,
    address chosenUniswapV3Factory,
    address chosenNative
  )
    TimeswapV2PeripheryWithdraw(chosenOptionFactory, chosenTokens)
    NativeImmutableState(chosenNative)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  /// @inheritdoc ITimeswapV2PeripheryUniswapV3Withdraw
  function withdraw(
    TimeswapV2PeripheryUniswapV3WithdrawParam calldata param
  ) external override returns (uint256 tokenAmount) {
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

    (uint256 token0Amount, uint256 token1Amount) = withdraw(
      TimeswapV2PeripheryWithdrawParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.isToken0 ? param.to : address(this),
        token1To: param.isToken0 ? address(this) : param.to,
        positionAmount: param.positionAmount
      })
    );

    tokenAmount = swapGetTotalToken(
      param.token0,
      param.token1,
      param.strike,
      param.uniswapV3Fee,
      param.to,
      param.isToken0,
      token0Amount,
      token1Amount,
      true
    );

    if (tokenAmount < param.minTokenAmount) revert MinTokenReached(tokenAmount, param.minTokenAmount);

    emit Withdraw(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      param.uniswapV3Fee,
      param.to,
      param.isToken0,
      tokenAmount,
      param.positionAmount
    );
  }
}

