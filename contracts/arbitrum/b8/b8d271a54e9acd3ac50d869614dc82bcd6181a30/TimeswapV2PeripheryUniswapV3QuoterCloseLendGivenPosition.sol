// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryQuoterCloseLendGivenPosition} from "./TimeswapV2PeripheryQuoterCloseLendGivenPosition.sol";

import {TimeswapV2PeripheryCloseLendGivenPositionParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam} from "./InternalParam.sol";

import {UniswapV3CalculateSwapGivenBalanceLimitParam} from "./SwapParam.sol";

import {ITimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPosition} from "./ITimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPosition.sol";

import {Verify} from "./libraries_Verify.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";
import {UniswapV3QuoterCallback} from "./UniswapV3SwapQuoterCallback.sol";
import {SwapCalculatorGivenBalanceLimit} from "./SwapCalculator.sol";
import {SwapQuoterGetTotalToken} from "./SwapCalculatorQuoter.sol";
import {Multicall} from "./Multicall.sol";

import {TimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPositionParam} from "./QuoterParam.sol";

contract TimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPosition is
  ITimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPosition,
  TimeswapV2PeripheryQuoterCloseLendGivenPosition,
  OnlyOperatorReceiver,
  UniswapV3QuoterCallback,
  SwapCalculatorGivenBalanceLimit,
  SwapQuoterGetTotalToken,
  Multicall
{
  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenUniswapV3Factory
  )
    TimeswapV2PeripheryQuoterCloseLendGivenPosition(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  /// @inheritdoc ITimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPosition
  function closeLendGivenPosition(
    TimeswapV2PeripheryUniswapV3QuoterCloseLendGivenPositionParam memory param,
    uint96 durationForward
  ) external returns (uint256 tokenAmount, uint160 timeswapV2SqrtInterestRateAfter, uint160 uniswapV3SqrtPriceAfter) {
    bytes memory data = abi.encode(param.uniswapV3Fee, param.isToken0);

    uint256 token0Amount;
    uint256 token1Amount;
    (token0Amount, token1Amount, data, timeswapV2SqrtInterestRateAfter) = closeLendGivenPosition(
      TimeswapV2PeripheryCloseLendGivenPositionParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.isToken0 ? param.to : address(this),
        token1To: param.isToken0 ? address(this) : param.to,
        positionAmount: param.positionAmount,
        data: data
      }),
      durationForward
    );

    (tokenAmount, uniswapV3SqrtPriceAfter) = quoteSwapGetTotalToken(
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

