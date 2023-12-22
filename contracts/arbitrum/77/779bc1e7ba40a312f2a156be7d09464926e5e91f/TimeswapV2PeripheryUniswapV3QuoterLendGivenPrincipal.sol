// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Math} from "./Math.sol";

import {TimeswapV2PeripheryLendGivenPrincipal} from "./TimeswapV2PeripheryLendGivenPrincipal.sol";

import {TimeswapV2PeripheryLendGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryLendGivenPrincipalInternalParam} from "./InternalParam.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3PoolQuoterLibrary} from "./UniswapV3PoolQuoter.sol";

import {TimeswapV2PeripheryQuoterLendGivenPrincipal} from "./TimeswapV2PeripheryQuoterLendGivenPrincipal.sol";

import {ITimeswapV2PeripheryUniswapV3QuoterLendGivenPrincipal} from "./ITimeswapV2PeripheryUniswapV3QuoterLendGivenPrincipal.sol";

import {TimeswapV2PeripheryUniswapV3QuoterLendGivenPrincipalParam} from "./QuoterParam.sol";
import {UniswapV3SwapParam} from "./SwapParam.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";
import {UniswapV3QuoterCallbackWithNative} from "./UniswapV3SwapQuoterCallback.sol";
import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryUniswapV3QuoterLendGivenPrincipal is
  ITimeswapV2PeripheryUniswapV3QuoterLendGivenPrincipal,
  TimeswapV2PeripheryQuoterLendGivenPrincipal,
  UniswapV3QuoterCallbackWithNative,
  Multicall
{
  using UniswapV3PoolQuoterLibrary for address;
  using Math for uint256;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenUniswapV3Factory
  )
    TimeswapV2PeripheryQuoterLendGivenPrincipal(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  function lendGivenPrincipal(
    TimeswapV2PeripheryUniswapV3QuoterLendGivenPrincipalParam calldata param,
    uint96 durationForward
  )
    external
    override
    returns (uint256 positionAmount, uint160 timeswapV2SqrtInterestRateAfter, uint160 uniswapV3SqrtPriceAfter)
  {
    address pool = UniswapV3FactoryLibrary.getWithCheck(
      uniswapV3Factory,
      param.token0,
      param.token1,
      param.uniswapV3Fee
    );

    bytes memory data = abi.encode(msg.sender, param.token0, param.token1, param.uniswapV3Fee);
    data = abi.encode(true, data);

    uint256 tokenAmountIn;
    uint256 tokenAmountOut;
    (tokenAmountIn, tokenAmountOut, uniswapV3SqrtPriceAfter) = pool.quoteSwap(
      UniswapV3SwapParam({
        recipient: address(this),
        zeroForOne: param.isToken0,
        exactInput: true,
        amount: param.tokenAmount,
        strikeLimit: param.strike,
        data: data
      })
    );

    data = abi.encode(msg.sender, param.isToken0);

    (positionAmount, , timeswapV2SqrtInterestRateAfter) = lendGivenPrincipal(
      TimeswapV2PeripheryLendGivenPrincipalParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        to: param.to,
        token0Amount: param.isToken0 ? param.tokenAmount.unsafeSub(tokenAmountIn) : tokenAmountOut,
        token1Amount: param.isToken0 ? tokenAmountOut : param.tokenAmount.unsafeSub(tokenAmountIn),
        data: data
      }),
      durationForward
    );
  }

  function timeswapV2PeripheryLendGivenPrincipalInternal(
    TimeswapV2PeripheryLendGivenPrincipalInternalParam memory
  ) internal override returns (bytes memory) {}
}

