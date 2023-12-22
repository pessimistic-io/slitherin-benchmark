// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Math} from "./Math.sol";
import {StrikeConversion} from "./StrikeConversion.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam, TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam} from "./InternalParam.sol";

import {ITimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal} from "./TimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";

import {UniswapV3PoolQuoterLibrary} from "./UniswapV3PoolQuoter.sol";
import {Verify} from "./libraries_Verify.sol";

import {TimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipalParam} from "./QuoterParam.sol";
import {UniswapV3SwapParam} from "./SwapParam.sol";

import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";
import {UniswapV3QuoterCallbackWithNative} from "./UniswapV3SwapQuoterCallback.sol";
import {Multicall} from "./Multicall.sol";

/// @title Capable of intializing a Timeswap V2 pool and adding liquidity
/// @author Timeswap Labs
contract TimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipal is
  ITimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipal,
  TimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal,
  UniswapV3QuoterCallbackWithNative,
  Multicall
{
  using UniswapV3PoolQuoterLibrary for address;
  using Math for uint256;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenLiquidityTokens,
    address chosenUniswapV3Factory
  )
    TimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal(chosenOptionFactory, chosenPoolFactory, chosenLiquidityTokens)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  ///  @inheritdoc ITimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipal
  function initialize(
    address token0,
    address token1,
    uint256 strike,
    uint256 maturity,
    uint160 rate
  ) external override {
    (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, token0, token1);

    ITimeswapV2Pool(poolPair).initialize(strike, maturity, rate);
  }

  struct Cache {
    uint256 tokenAmountIn;
    uint256 tokenAmountOut;
  }

  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryUniswapV3QuoterAddLiquidityGivenPrincipalParam calldata param,
    uint96 durationForward
  )
    external
    override
    returns (
      uint160 liquidityAmount,
      uint256 excessLong0Amount,
      uint256 excessLong1Amount,
      uint256 excessShortAmount,
      uint160 timeswapV2LiquidityAfter,
      uint160 uniswapV3SqrtPriceAfter
    )
  {
    address pool = UniswapV3FactoryLibrary.getWithCheck(
      uniswapV3Factory,
      param.token0,
      param.token1,
      param.uniswapV3Fee
    );

    bytes memory data = abi.encode(msg.sender, param.token0, param.token1, param.uniswapV3Fee);
    data = abi.encode(true, data);

    Cache memory cache;
    (cache.tokenAmountIn, cache.tokenAmountOut, uniswapV3SqrtPriceAfter) = pool.quoteSwap(
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

    (
      liquidityAmount,
      excessLong0Amount,
      excessLong1Amount,
      excessShortAmount,
      ,
      timeswapV2LiquidityAfter
    ) = addLiquidityGivenPrincipal(
      TimeswapV2PeripheryAddLiquidityGivenPrincipalParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        liquidityTo: param.liquidityTo,
        token0Amount: param.isToken0 ? param.tokenAmount.unsafeSub(cache.tokenAmountIn) : cache.tokenAmountOut,
        token1Amount: param.isToken0 ? cache.tokenAmountOut : param.tokenAmount.unsafeSub(cache.tokenAmountIn),
        data: data
      }),
      durationForward
    );
  }

  function timeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam memory param
  ) internal pure override returns (uint256 token0Amount, uint256 token1Amount, bytes memory data) {
    (, bool isToken0) = abi.decode(param.data, (address, bool));

    uint256 maxPreferredTokenAmount = StrikeConversion.turn(param.tokenAmount, param.strike, isToken0, true);

    uint256 preferredTokenAmount = isToken0 ? param.token1Amount : param.token0Amount;
    uint256 otherTokenAmount;

    if (maxPreferredTokenAmount <= preferredTokenAmount) preferredTokenAmount = maxPreferredTokenAmount;
    else
      otherTokenAmount = StrikeConversion.dif(param.tokenAmount, preferredTokenAmount, param.strike, !isToken0, true);

    token0Amount = isToken0 ? otherTokenAmount : preferredTokenAmount;
    token1Amount = isToken0 ? preferredTokenAmount : otherTokenAmount;

    data = bytes("");
  }

  function timeswapV2PeripheryAddLiquidityGivenPrincipalInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam memory param
  ) internal override returns (bytes memory data) {}
}

