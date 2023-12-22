// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Error} from "./Error.sol";
import {Math} from "./Math.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryCloseLendGivenPosition} from "./TimeswapV2PeripheryCloseLendGivenPosition.sol";

import {TimeswapV2PeripheryCloseLendGivenPositionParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam} from "./InternalParam.sol";

import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";
import {UniswapV3CalculateSwapGivenBalanceLimitParam} from "./SwapParam.sol";

import {ITimeswapV2PeripheryUniswapV3CloseLendGivenPosition} from "./ITimeswapV2PeripheryUniswapV3CloseLendGivenPosition.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {NativeImmutableState, NativeWithdraws} from "./Native.sol";
import {UniswapImmutableState, UniswapV3Callback} from "./UniswapV3SwapCallback.sol";
import {SwapCalculatorGivenBalanceLimit, SwapGetTotalToken} from "./SwapCalculator.sol";
import {Multicall} from "./Multicall.sol";

import {TimeswapV2PeripheryUniswapV3CloseLendGivenPositionParam} from "./structs_Param.sol";

/// @title Capable of closing a lend position given a Timeswap V2 Position
/// @author Timeswap Labs
contract TimeswapV2PeripheryUniswapV3CloseLendGivenPosition is
  ITimeswapV2PeripheryUniswapV3CloseLendGivenPosition,
  TimeswapV2PeripheryCloseLendGivenPosition,
  OnlyOperatorReceiver,
  NativeImmutableState,
  NativeWithdraws,
  UniswapV3Callback,
  SwapCalculatorGivenBalanceLimit,
  SwapGetTotalToken,
  Multicall
{
  using UniswapV3PoolLibrary for address;
  using Math for uint256;
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenUniswapV3Factory,
    address chosenNative
  )
    TimeswapV2PeripheryCloseLendGivenPosition(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    NativeImmutableState(chosenNative)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  /// @inheritdoc ITimeswapV2PeripheryUniswapV3CloseLendGivenPosition
  function closeLendGivenPosition(
    TimeswapV2PeripheryUniswapV3CloseLendGivenPositionParam memory param
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
        position: TimeswapV2OptionPosition.Short
      }),
      param.positionAmount
    );

    bytes memory data = abi.encode(param.uniswapV3Fee, param.isToken0);

    uint256 token0Amount;
    uint256 token1Amount;
    (token0Amount, token1Amount, data) = closeLendGivenPosition(
      TimeswapV2PeripheryCloseLendGivenPositionParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.isToken0 ? param.to : address(this),
        token1To: param.isToken0 ? address(this) : param.to,
        positionAmount: param.positionAmount,
        data: data
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
      abi.decode(data, (bool))
    );

    if (tokenAmount < param.minTokenAmount) revert MinTokenReached(tokenAmount, param.minTokenAmount);

    emit CloseLendGivenPosition(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      param.uniswapV3Fee,
      msg.sender,
      param.to,
      param.isToken0,
      tokenAmount,
      param.positionAmount
    );
  }

  function timeswapV2PeripheryCloseLendGivenPositionChoiceInternal(
    TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam memory param
  ) internal override returns (uint256 token0Amount, uint256 token1Amount, bytes memory data) {
    (uint24 uniswapV3Fee, bool isToken0) = abi.decode(param.data, (uint24, bool));

    bool removeStrikeLimit;
    (removeStrikeLimit, token0Amount, token1Amount) = calculateSwapGivenBalanceLimit(
      UniswapV3CalculateSwapGivenBalanceLimitParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        uniswapV3Fee: uniswapV3Fee,
        isToken0: isToken0,
        token0Balance: param.token0Balance,
        token1Balance: param.token1Balance,
        tokenAmount: param.tokenAmount
      })
    );

    data = abi.encode(removeStrikeLimit);
  }
}

