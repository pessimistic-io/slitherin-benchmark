// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {StrikeConversion} from "./StrikeConversion.sol";
import {Error} from "./Error.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipalParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam, TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam} from "./InternalParam.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipal} from "./TimeswapV2PeripheryAddLiquidityGivenPrincipal.sol";

import {ITimeswapV2PeripheryNoDexAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryNoDexAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryNoDexAddLiquidityGivenPrincipalParam} from "./structs_Param.sol";

import {NativeImmutableState, NativePayments} from "./Native.sol";
import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryNoDexAddLiquidityGivenPrincipal is
  ITimeswapV2PeripheryNoDexAddLiquidityGivenPrincipal,
  TimeswapV2PeripheryAddLiquidityGivenPrincipal,
  NativeImmutableState,
  Multicall,
  NativePayments
{
  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenLiquidityTokens,
    address chosenNative
  )
    TimeswapV2PeripheryAddLiquidityGivenPrincipal(
      chosenOptionFactory,
      chosenPoolFactory,
      chosenTokens,
      chosenLiquidityTokens
    )
    NativeImmutableState(chosenNative)
  {}

  /// @inheritdoc ITimeswapV2PeripheryNoDexAddLiquidityGivenPrincipal
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

  /// @inheritdoc ITimeswapV2PeripheryNoDexAddLiquidityGivenPrincipal
  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryNoDexAddLiquidityGivenPrincipalParam calldata param
  ) external payable returns (uint160 liquidityAmount, uint256 excessLongAmount, uint256 excessShortAmount) {
    if (param.deadline < block.timestamp) Error.deadlineReached(param.deadline);

    {
      (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

      uint160 sqrtInterestRate = ITimeswapV2Pool(poolPair).sqrtInterestRate(param.strike, param.maturity);

      if (sqrtInterestRate < param.minSqrtInterestRate)
        revert MinSqrtInterestRateReached(sqrtInterestRate, param.minSqrtInterestRate);
      if (sqrtInterestRate > param.maxSqrtInterestRate)
        revert MaxSqrtInterestRateReached(sqrtInterestRate, param.maxSqrtInterestRate);

      bytes memory data = abi.encode(msg.sender, param.isToken0);

      uint256 excessLong0Amount;
      uint256 excessLong1Amount;
      (liquidityAmount, excessLong0Amount, excessLong1Amount, excessShortAmount, ) = addLiquidityGivenPrincipal(
        TimeswapV2PeripheryAddLiquidityGivenPrincipalParam({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity,
          liquidityTo: param.liquidityTo,
          token0Amount: param.isToken0 ? param.tokenAmount : 0,
          token1Amount: param.isToken0 ? 0 : param.tokenAmount,
          data: data,
          erc1155Data: param.erc1155Data
        })
      );

      excessLongAmount = param.isToken0 ? excessLong0Amount : excessLong1Amount;
    }

    if (liquidityAmount < param.minLiquidityAmount)
      revert MinLiquidityReached(liquidityAmount, param.minLiquidityAmount);

    emit AddLiquidityGivenPrincipal(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      msg.sender,
      param.liquidityTo,
      param.isToken0,
      param.tokenAmount,
      liquidityAmount,
      excessLongAmount,
      excessShortAmount
    );
  }

  function timeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam memory param
  ) internal pure override returns (uint256 token0Amount, uint256 token1Amount, bytes memory data) {
    (, bool isToken0) = abi.decode(param.data, (address, bool));

    uint256 tokenAmount = StrikeConversion.turn(param.tokenAmount, param.strike, !isToken0, true);

    token0Amount = isToken0 ? tokenAmount : 0;
    token1Amount = isToken0 ? 0 : tokenAmount;

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

    data = bytes("");
  }
}

