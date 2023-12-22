// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Math} from "./Math.sol";

import {Error} from "./Error.sol";
import {StrikeConversion} from "./StrikeConversion.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {TimeswapV2PeripheryCloseBorrowGivenPosition} from "./TimeswapV2PeripheryCloseBorrowGivenPosition.sol";

import {TimeswapV2PeripheryCloseBorrowGivenPositionParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PeripheryCloseBorrowGivenPositionChoiceInternalParam, TimeswapV2PeripheryCloseBorrowGivenPositionInternalParam} from "./InternalParam.sol";

import {ITimeswapV2PeripheryNoDexCloseBorrowGivenPosition} from "./ITimeswapV2PeripheryNoDexCloseBorrowGivenPosition.sol";

import {TimeswapV2PeripheryNoDexCloseBorrowGivenPositionParam} from "./structs_Param.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {NativeImmutableState, NativeWithdraws, NativePayments} from "./Native.sol";
import {Multicall} from "./Multicall.sol";

/// @title Capable of closing a borrow position given a Timeswap V2 Position
/// @author Timeswap Labs
contract TimeswapV2PeripheryNoDexCloseBorrowGivenPosition is
  ITimeswapV2PeripheryNoDexCloseBorrowGivenPosition,
  TimeswapV2PeripheryCloseBorrowGivenPosition,
  OnlyOperatorReceiver,
  NativeImmutableState,
  NativeWithdraws,
  NativePayments,
  Multicall
{
  using Math for uint256;
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenNative
  )
    TimeswapV2PeripheryCloseBorrowGivenPosition(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    NativeImmutableState(chosenNative)
  {}

  /// @inheritdoc ITimeswapV2PeripheryNoDexCloseBorrowGivenPosition
  function closeBorrowGivenPosition(
    TimeswapV2PeripheryNoDexCloseBorrowGivenPositionParam calldata param
  ) external returns (uint256 tokenAmount) {
    if (param.deadline < block.timestamp) Error.deadlineReached(param.deadline);

    ITimeswapV2Token(tokens).transferTokenPositionFrom(
      msg.sender,
      address(this),
      TimeswapV2TokenPosition({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        position: param.isLong0 ? TimeswapV2OptionPosition.Long0 : TimeswapV2OptionPosition.Long1
      }),
      param.positionAmount
    );

    bytes memory data = abi.encode(msg.sender, param.to, param.isToken0);

    (, , data) = closeBorrowGivenPosition(
      TimeswapV2PeripheryCloseBorrowGivenPositionParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        to: (param.isToken0 == param.isLong0) ? address(this) : param.to,
        isLong0: param.isLong0,
        positionAmount: param.positionAmount,
        data: data
      })
    );

    tokenAmount = abi.decode(data, (uint256));

    if (tokenAmount > param.maxTokenAmount) revert MaxTokenReached(tokenAmount, param.maxTokenAmount);

    emit CloseBorrowGivenPosition(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      msg.sender,
      param.to,
      param.isToken0,
      param.isLong0,
      tokenAmount,
      param.positionAmount
    );
  }

  function timeswapV2PeripheryCloseBorrowGivenPositionChoiceInternal(
    TimeswapV2PeripheryCloseBorrowGivenPositionChoiceInternalParam memory param
  ) internal pure override returns (uint256 token0Amount, uint256 token1Amount, bytes memory data) {
    (, , bool isToken0) = abi.decode(param.data, (address, address, bool));

    uint256 tokenAmount = StrikeConversion.turn(param.tokenAmount, param.strike, !isToken0, true);

    token0Amount = isToken0 ? tokenAmount : 0;
    token1Amount = isToken0 ? 0 : tokenAmount;

    data = param.data;
  }

  function timeswapV2PeripheryCloseBorrowGivenPositionInternal(
    TimeswapV2PeripheryCloseBorrowGivenPositionInternalParam memory param
  ) internal override returns (bytes memory data) {
    (address msgSender, address to, bool isToken0) = abi.decode(param.data, (address, address, bool));
    uint256 tokenAmount = isToken0 ? param.token0Amount : param.token1Amount;
    if (isToken0 == param.isLong0) tokenAmount = param.positionAmount - tokenAmount;

    if (isToken0 == param.isLong0) {
      if (param.positionAmount > tokenAmount)
        IERC20(isToken0 ? param.token0 : param.token1).safeTransfer(to, param.positionAmount.unsafeSub(tokenAmount));
      else revert();
    } else
      pay(
        isToken0 ? param.token0 : param.token1,
        msgSender,
        param.optionPair,
        isToken0 ? param.token0Amount : param.token1Amount
      );

    data = abi.encode(isToken0 ? param.token0Amount : param.token1Amount);
  }
}

