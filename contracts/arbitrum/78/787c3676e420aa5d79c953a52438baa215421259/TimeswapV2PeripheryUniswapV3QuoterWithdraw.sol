// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";

import {TimeswapV2PeripheryQuoterWithdraw} from "./TimeswapV2PeripheryQuoterWithdraw.sol";

import {TimeswapV2PeripheryWithdrawParam} from "./structs_Param.sol";

import {ITimeswapV2PeripheryUniswapV3QuoterWithdraw} from "./ITimeswapV2PeripheryUniswapV3QuoterWithdraw.sol";

import {TimeswapV2PeripheryUniswapV3QuoterWithdrawParam} from "./QuoterParam.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";
import {UniswapV3QuoterCallback} from "./UniswapV3SwapQuoterCallback.sol";
import {SwapQuoterGetTotalToken} from "./SwapCalculatorQuoter.sol";
import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryUniswapV3QuoterWithdraw is
  TimeswapV2PeripheryQuoterWithdraw,
  ITimeswapV2PeripheryUniswapV3QuoterWithdraw,
  OnlyOperatorReceiver,
  UniswapV3QuoterCallback,
  SwapQuoterGetTotalToken,
  Multicall
{
  constructor(
    address chosenOptionFactory,
    address chosenTokens,
    address chosenUniswapV3Factory
  )
    TimeswapV2PeripheryQuoterWithdraw(chosenOptionFactory, chosenTokens)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  function withdraw(
    TimeswapV2PeripheryUniswapV3QuoterWithdrawParam calldata param
  ) external override returns (uint256 tokenAmount, uint160 uniswapV3SqrtPriceAfter) {
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

    (tokenAmount, uniswapV3SqrtPriceAfter) = quoteSwapGetTotalToken(
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
  }
}

