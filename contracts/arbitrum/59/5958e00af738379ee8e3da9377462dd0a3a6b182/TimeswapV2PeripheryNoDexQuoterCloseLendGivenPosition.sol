// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryQuoterCloseLendGivenPosition} from "./TimeswapV2PeripheryQuoterCloseLendGivenPosition.sol";

import {TimeswapV2PeripheryCloseLendGivenPositionParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam} from "./InternalParam.sol";
import {StrikeConversion} from "./StrikeConversion.sol";

import {ITimeswapV2PeripheryNoDexQuoterCloseLendGivenPosition} from "./ITimeswapV2PeripheryNoDexQuoterCloseLendGivenPosition.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";

import {Multicall} from "./Multicall.sol";

import {TimeswapV2PeripheryNoDexQuoterCloseLendGivenPositionParam} from "./QuoterParam.sol";

contract TimeswapV2PeripheryNoDexQuoterCloseLendGivenPosition is
  ITimeswapV2PeripheryNoDexQuoterCloseLendGivenPosition,
  TimeswapV2PeripheryQuoterCloseLendGivenPosition,
  OnlyOperatorReceiver,
  Multicall
{
  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens
  ) TimeswapV2PeripheryQuoterCloseLendGivenPosition(chosenOptionFactory, chosenPoolFactory, chosenTokens) {}

  /// @inheritdoc ITimeswapV2PeripheryNoDexQuoterCloseLendGivenPosition
  function closeLendGivenPosition(
    TimeswapV2PeripheryNoDexQuoterCloseLendGivenPositionParam memory param,
    uint96 durationForward
  ) external returns (uint256 token0Amount, uint256 token1Amount, uint160 timeswapV2SqrtInterestRateAfter) {
    bytes memory data = abi.encode(param.isToken0);

    (token0Amount, token1Amount, data, timeswapV2SqrtInterestRateAfter) = closeLendGivenPosition(
      TimeswapV2PeripheryCloseLendGivenPositionParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.to,
        token1To: param.to,
        positionAmount: param.positionAmount,
        data: data
      }),
      durationForward
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

