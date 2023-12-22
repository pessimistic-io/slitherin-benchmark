// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {StrikeConversion} from "./StrikeConversion.sol";
import {Error} from "./Error.sol";
import {Math} from "./Math.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipalParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam, TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam} from "./InternalParam.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipal} from "./TimeswapV2PeripheryAddLiquidityGivenPrincipal.sol";

import {ITimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipal.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";

import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";

import {TimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipalParam} from "./structs_Param.sol";
import {UniswapV3SwapParam} from "./SwapParam.sol";

import {NativeImmutableState} from "./Native.sol";
import {UniswapImmutableState, UniswapV3CallbackWithNative} from "./UniswapV3SwapCallback.sol";
import {Multicall} from "./Multicall.sol";

/// @title Capable of intializing a Timeswap V2 pool and adding liquidity
/// @author Timeswap Labs
contract TimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipal is
  ITimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipal,
  TimeswapV2PeripheryAddLiquidityGivenPrincipal,
  NativeImmutableState,
  UniswapV3CallbackWithNative,
  Multicall
{
  using UniswapV3PoolLibrary for address;
  using Math for uint256;
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenLiquidityTokens,
    address chosenUniswapV3Factory,
    address chosenNative
  )
    TimeswapV2PeripheryAddLiquidityGivenPrincipal(chosenOptionFactory, chosenPoolFactory, chosenLiquidityTokens)
    NativeImmutableState(chosenNative)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  ///  @inheritdoc ITimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipal
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

  ///  @inheritdoc ITimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipal
  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryUniswapV3AddLiquidityGivenPrincipalParam calldata param
  )
    external
    payable
    override
    returns (uint160 liquidityAmount, uint256 excessLong0Amount, uint256 excessLong1Amount, uint256 excessShortAmount)
  {
    if (param.deadline < block.timestamp) Error.deadlineReached(param.deadline);

    {
      (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

      uint160 sqrtInterestRate = ITimeswapV2Pool(poolPair).sqrtInterestRate(param.strike, param.maturity);

      if (sqrtInterestRate < param.minSqrtInterestRate)
        revert MinSqrtInterestRateReached(sqrtInterestRate, param.minSqrtInterestRate);
      if (sqrtInterestRate > param.maxSqrtInterestRate)
        revert MaxSqrtInterestRateReached(sqrtInterestRate, param.maxSqrtInterestRate);

      address pool = UniswapV3FactoryLibrary.getWithCheck(
        uniswapV3Factory,
        param.token0,
        param.token1,
        param.uniswapV3Fee
      );

      bytes memory data = abi.encode(msg.sender, param.token0, param.token1, param.uniswapV3Fee);
      data = abi.encode(true, data);

      (uint256 tokenAmountIn, uint256 tokenAmountOut) = pool.swap(
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

      (liquidityAmount, excessLong0Amount, excessLong1Amount, excessShortAmount, ) = addLiquidityGivenPrincipal(
        TimeswapV2PeripheryAddLiquidityGivenPrincipalParam({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity,
          liquidityTo: param.liquidityTo,
          token0Amount: param.isToken0 ? param.tokenAmount.unsafeSub(tokenAmountIn) : tokenAmountOut,
          token1Amount: param.isToken0 ? tokenAmountOut : param.tokenAmount.unsafeSub(tokenAmountIn),
          data: data
        })
      );
    }

    if (liquidityAmount < param.minLiquidityAmount)
      revert MinLiquidityReached(liquidityAmount, param.minLiquidityAmount);

    emit AddLiquidityGivenPrincipal(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      param.uniswapV3Fee,
      msg.sender,
      param.liquidityTo,
      param.isToken0,
      param.tokenAmount,
      liquidityAmount,
      excessLong0Amount,
      excessLong1Amount,
      excessShortAmount
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

    data = param.data;
  }

  function timeswapV2PeripheryAddLiquidityGivenPrincipalInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam memory param
  ) internal override returns (bytes memory data) {
    (address msgSender, bool isToken0) = abi.decode(param.data, (address, bool));

    if ((isToken0 ? param.token0Amount : param.token1Amount) != 0)
      pay(
        isToken0 ? param.token0 : param.token1,
        msgSender,
        param.optionPair,
        isToken0 ? param.token0Amount : param.token1Amount
      );

    if ((isToken0 ? param.token1Amount : param.token0Amount) != 0)
      IERC20(isToken0 ? param.token1 : param.token0).safeTransfer(
        param.optionPair,
        isToken0 ? param.token1Amount : param.token0Amount
      );

    data = bytes("");
  }
}

