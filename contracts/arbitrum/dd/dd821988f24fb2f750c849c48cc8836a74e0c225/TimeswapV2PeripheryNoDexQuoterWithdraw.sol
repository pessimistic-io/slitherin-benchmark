// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryQuoterWithdraw} from "./TimeswapV2PeripheryQuoterWithdraw.sol";

import {TimeswapV2PeripheryWithdrawParam} from "./structs_Param.sol";

import {ITimeswapV2PeripheryNoDexQuoterWithdraw} from "./ITimeswapV2PeripheryNoDexQuoterWithdraw.sol";

import {TimeswapV2PeripheryNoDexQuoterWithdrawParam} from "./QuoterParam.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";

import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryNoDexQuoterWithdraw is
  TimeswapV2PeripheryQuoterWithdraw,
  ITimeswapV2PeripheryNoDexQuoterWithdraw,
  OnlyOperatorReceiver,
  Multicall
{
  constructor(
    address chosenOptionFactory,
    address chosenTokens
  ) TimeswapV2PeripheryQuoterWithdraw(chosenOptionFactory, chosenTokens) {}

  function withdraw(
    TimeswapV2PeripheryNoDexQuoterWithdrawParam calldata param
  ) external override returns (uint256 token0Amount, uint256 token1Amount) {
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
  }
}

