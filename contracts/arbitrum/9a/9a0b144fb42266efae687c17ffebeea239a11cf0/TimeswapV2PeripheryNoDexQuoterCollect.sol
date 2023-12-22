// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2PeripheryQuoterCollect} from "./TimeswapV2PeripheryQuoterCollect.sol";

import {TimeswapV2PeripheryCollectParam} from "./structs_Param.sol";

import {ITimeswapV2PeripheryNoDexQuoterCollect} from "./ITimeswapV2PeripheryNoDexQuoterCollect.sol";

import {TimeswapV2PeripheryNoDexQuoterCollectParam} from "./QuoterParam.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryNoDexQuoterCollect is
  TimeswapV2PeripheryQuoterCollect,
  ITimeswapV2PeripheryNoDexQuoterCollect,
  OnlyOperatorReceiver,
  Multicall
{
  constructor(
    address chosenOptionFactory,
    address chosenTokens,
    address chosenLiquidityTokens
  ) TimeswapV2PeripheryQuoterCollect(chosenOptionFactory, chosenTokens, chosenLiquidityTokens) {}

  function collect(
    TimeswapV2PeripheryNoDexQuoterCollectParam calldata param
  ) external returns (uint256 token0Amount, uint256 token1Amount) {
    (token0Amount, token1Amount) = collect(
      TimeswapV2PeripheryCollectParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.isToken0 ? param.to : address(this),
        token1To: param.isToken0 ? address(this) : param.to,
        excessShortAmount: param.excessShortAmount
      })
    );
  }
}

