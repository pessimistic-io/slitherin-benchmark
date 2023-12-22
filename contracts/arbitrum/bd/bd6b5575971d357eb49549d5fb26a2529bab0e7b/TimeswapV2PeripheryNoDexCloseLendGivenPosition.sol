// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Error} from "./Error.sol";
import {Math} from "./Math.sol";

import {StrikeConversion} from "./StrikeConversion.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryCloseLendGivenPosition} from "./TimeswapV2PeripheryCloseLendGivenPosition.sol";

import {TimeswapV2PeripheryCloseLendGivenPositionParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam} from "./InternalParam.sol";

import {ITimeswapV2PeripheryNoDexCloseLendGivenPosition} from "./ITimeswapV2PeripheryNoDexCloseLendGivenPosition.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {NativeImmutableState, NativeWithdraws, NativePayments} from "./Native.sol";
import {Multicall} from "./Multicall.sol";

import {TimeswapV2PeripheryNoDexCloseLendGivenPositionParam} from "./structs_Param.sol";

/// @title Capable of closing a lend position given a Timeswap V2 Position
/// @author Timeswap Labs
contract TimeswapV2PeripheryNoDexCloseLendGivenPosition is
  ITimeswapV2PeripheryNoDexCloseLendGivenPosition,
  TimeswapV2PeripheryCloseLendGivenPosition,
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
    TimeswapV2PeripheryCloseLendGivenPosition(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    NativeImmutableState(chosenNative)
  {}

  /// @inheritdoc ITimeswapV2PeripheryNoDexCloseLendGivenPosition
  function closeLendGivenPosition(
    TimeswapV2PeripheryNoDexCloseLendGivenPositionParam memory param
  ) external returns (uint256 token0Amount, uint256 token1Amount) {
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

    bytes memory data = abi.encode(param.isToken0);

    (token0Amount, token1Amount, data) = closeLendGivenPosition(
      TimeswapV2PeripheryCloseLendGivenPositionParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.to,
        token1To: param.to,
        positionAmount: param.positionAmount,
        data: data
      })
    );

    if (token0Amount < param.minToken0Amount) revert MinTokenReached(token0Amount, param.minToken0Amount);
    if (token1Amount < param.minToken1Amount) revert MinTokenReached(token1Amount, param.minToken1Amount);

    emit CloseLendGivenPosition(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      msg.sender,
      param.to,
      token0Amount,
      token1Amount,
      param.positionAmount
    );
  }

  function timeswapV2PeripheryCloseLendGivenPositionChoiceInternal(
    TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam memory param
  ) internal pure override returns (uint256 token0Amount, uint256 token1Amount, bytes memory data) {
    bool isToken0 = abi.decode(param.data, (bool));
    uint256 maxPrefferedTokenAmount = StrikeConversion.turn(param.tokenAmount, param.strike, !isToken0, false);
    uint256 prefferedTokenAmount = isToken0 ? param.token0Balance : param.token1Balance;
    uint256 otherTokenAmount;
    if (maxPrefferedTokenAmount <= prefferedTokenAmount) prefferedTokenAmount = maxPrefferedTokenAmount;
    else
      otherTokenAmount = StrikeConversion.dif(param.tokenAmount, prefferedTokenAmount, param.strike, isToken0, false);

    token0Amount = isToken0 ? prefferedTokenAmount : otherTokenAmount;
    token1Amount = isToken0 ? otherTokenAmount : prefferedTokenAmount;

    data = bytes("");
  }
}

