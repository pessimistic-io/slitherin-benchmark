// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryQuoterShortAfterMaturity} from "./TimeswapV2PeripheryQuoterShortAfterMaturity.sol";

import {TimeswapV2PeripheryShortAfterMaturityParam} from "./structs_Param.sol";

import {ITimeswapV2PeripheryNoDexQuoterShortAfterMaturity} from "./ITimeswapV2PeripheryNoDexQuoterShortAfterMaturity.sol";

import {TimeswapV2PeripheryNoDexQuoterShortAfterMaturityParam} from "./QuoterParam.sol";

import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryNoDexQuoterShortAfterMaturity is
  TimeswapV2PeripheryQuoterShortAfterMaturity,
  ITimeswapV2PeripheryNoDexQuoterShortAfterMaturity,
  Multicall
{
  constructor(address chosenOptionFactory) TimeswapV2PeripheryQuoterShortAfterMaturity(chosenOptionFactory) {}

  function shortAfterMaturity(
    TimeswapV2PeripheryNoDexQuoterShortAfterMaturityParam calldata param
  ) external override returns (uint256 token0Amount, uint256 token1Amount) {
    (token0Amount, token1Amount) = shortAfterMaturity(
      TimeswapV2PeripheryShortAfterMaturityParam({
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

