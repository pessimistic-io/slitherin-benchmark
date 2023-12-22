// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {Math} from "./Math.sol";

import {TimeswapV2PeripheryLendGivenPrincipal} from "./TimeswapV2PeripheryLendGivenPrincipal.sol";

import {TimeswapV2PeripheryLendGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryLendGivenPrincipalInternalParam} from "./InternalParam.sol";

import {TimeswapV2PeripheryQuoterLendGivenPrincipal} from "./TimeswapV2PeripheryQuoterLendGivenPrincipal.sol";

import {Multicall} from "./Multicall.sol";
import {ITimeswapV2PeripheryNoDexQuoterLendGivenPrincipal} from "./ITimeswapV2PeripheryNoDexQuoterLendGivenPrincipal.sol";
import {TimeswapV2PeripheryNoDexQuoterLendGivenPrincipalParam} from "./QuoterParam.sol";

contract TimeswapV2PeripheryNoDexQuoterLendGivenPrincipal is
  ITimeswapV2PeripheryNoDexQuoterLendGivenPrincipal,
  TimeswapV2PeripheryQuoterLendGivenPrincipal,
  Multicall
{
  using Math for uint256;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens
  ) TimeswapV2PeripheryQuoterLendGivenPrincipal(chosenOptionFactory, chosenPoolFactory, chosenTokens) {}

  function lendGivenPrincipal(
    TimeswapV2PeripheryNoDexQuoterLendGivenPrincipalParam calldata param,
    uint96 durationForward
  ) external override returns (uint256 positionAmount, uint160 timeswapV2SqrtInterestRateAfter) {
    bytes memory data = abi.encode(msg.sender, param.isToken0);

    (positionAmount, , timeswapV2SqrtInterestRateAfter) = lendGivenPrincipal(
      TimeswapV2PeripheryLendGivenPrincipalParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        to: param.to,
        token0Amount: param.isToken0 ? param.tokenAmount : 0,
        token1Amount: param.isToken0 ? 0 : param.tokenAmount,
        data: data
      }),
      durationForward
    );
  }

  function timeswapV2PeripheryLendGivenPrincipalInternal(
    TimeswapV2PeripheryLendGivenPrincipalInternalParam memory
  ) internal override returns (bytes memory) {}
}

