// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Error} from "./Error.sol";
import {Math} from "./Math.sol";
import {StrikeConversion} from "./StrikeConversion.sol";
import {CatchError} from "./CatchError.sol";

import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";

import {TimeswapV2OptionMintParam} from "./structs_Param.sol";
import {TimeswapV2OptionMintCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2OptionMint} from "./enums_Transaction.sol";
import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {TimeswapV2PoolMintParam, TimeswapV2PoolAddFeesParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PoolMintChoiceCallbackParam, TimeswapV2PoolMintCallbackParam, TimeswapV2PoolAddFeesCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2PoolMint} from "./enums_Transaction.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";

import {TimeswapV2LiquidityTokenMintParam, TimeswapV2LiquidityTokenAddFeesParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2LiquidityTokenMintCallbackParam, TimeswapV2LiquidityTokenAddFeesCallbackParam} from "./contracts_structs_CallbackParam.sol";

import {ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam, TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam} from "./InternalParam.sol";

import {Verify} from "./libraries_Verify.sol";

/// @title Abstract contract which specifies functions that are required for liquidity provision which are to be inherited for a specific DEX/Aggregator implementation
abstract contract TimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal is
  ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal
{
  using Math for uint256;
  using CatchError for bytes;

  /* ===== MODEL ===== */

  /// @inheritdoc ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal
  address public immutable override poolFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal
  address public immutable override liquidityTokens;

  /* ===== INIT ===== */

  constructor(address chosenOptionFactory, address chosenPoolFactory, address chosenLiquidityTokens) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
    liquidityTokens = chosenLiquidityTokens;
  }

  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalParam memory param,
    uint96 durationForward
  )
    internal
    returns (
      uint160 liquidityAmount,
      uint256 excessLong0Amount,
      uint256 excessLong1Amount,
      uint256 excessShortAmount,
      bytes memory data,
      uint160 timeswapV2LiquidityAfter
    )
  {
    (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

    data = abi.encode(
      param.token0,
      param.token1,
      param.liquidityTo,
      param.token0Amount,
      param.token1Amount,
      param.data
    );

    try
      ITimeswapV2Pool(poolPair).mint(
        TimeswapV2PoolMintParam({
          strike: param.strike,
          maturity: param.maturity,
          to: address(this),
          transaction: TimeswapV2PoolMint.GivenLarger,
          delta: StrikeConversion.combine(param.token0Amount, param.token1Amount, param.strike, false),
          data: data
        }),
        durationForward
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassPoolMintCallbackInfo.selector);
      (liquidityAmount, excessLong0Amount, excessLong1Amount, excessShortAmount, timeswapV2LiquidityAfter, data) = abi
        .decode(data, (uint160, uint256, uint256, uint256, uint160, bytes));
    }
  }

  function timeswapV2PoolMintChoiceCallback(
    TimeswapV2PoolMintChoiceCallbackParam calldata param
  ) external override returns (uint256 long0Amount, uint256 long1Amount, bytes memory data) {
    address token0;
    address token1;
    address liquidityTo;
    uint256 token0Amount;
    uint256 token1Amount;
    (token0, token1, liquidityTo, token0Amount, token1Amount, data) = abi.decode(
      param.data,
      (address, address, address, uint256, uint256, bytes)
    );

    Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    bool isShortExcess;
    if (param.shortAmount > param.longAmount) {
      (long0Amount, long1Amount, data) = timeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternal(
        TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam({
          token0: token0,
          token1: token1,
          strike: param.strike,
          maturity: param.maturity,
          token0Amount: token0Amount,
          token1Amount: token1Amount,
          liquidityAmount: param.liquidityAmount,
          tokenAmount: param.longAmount,
          data: data
        })
      );

      Error.checkEnough(token0Amount, long0Amount);
      Error.checkEnough(token1Amount, long1Amount);

      isShortExcess = true;
    } else {
      long0Amount = token0Amount;
      long1Amount = token1Amount;
    }

    data = abi.encode(
      CacheForTimeswapV2PoolMintCallback(token0, token1, liquidityTo, isShortExcess, token0Amount, token1Amount),
      data
    );
  }

  struct CacheForTimeswapV2PoolMintCallback {
    address token0;
    address token1;
    address liquidityTo;
    bool isShortExcess;
    uint256 token0Amount;
    uint256 token1Amount;
  }

  /// @notice the abstract implementation for TimeswapV2PoolMintCallback
  /// @param param params for mintCallBack from TimeswapV2Pool
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PoolMintCallback(
    TimeswapV2PoolMintCallbackParam calldata param
  ) external override returns (bytes memory data) {
    CacheForTimeswapV2PoolMintCallback memory cache;
    (cache, data) = abi.decode(param.data, (CacheForTimeswapV2PoolMintCallback, bytes));

    address optionPair = Verify.timeswapV2Pool(optionFactory, poolFactory, cache.token0, cache.token1);

    data = abi.encode(cache.token0, cache.token1, param.liquidityAmount, data);

    uint256 shortAmountMinted;
    try
      ITimeswapV2Option(optionPair).mint(
        TimeswapV2OptionMintParam({
          strike: param.strike,
          maturity: param.maturity,
          long0To: cache.isShortExcess ? msg.sender : address(this),
          long1To: cache.isShortExcess ? msg.sender : address(this),
          shortTo: cache.isShortExcess ? address(this) : msg.sender,
          transaction: TimeswapV2OptionMint.GivenTokensAndLongs,
          amount0: cache.token0Amount,
          amount1: cache.token1Amount,
          data: data
        })
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassOptionMintCallbackInfo.selector);
      (shortAmountMinted, data) = abi.decode(data, (uint256, bytes));
    }

    uint256 excessLong0Amount;
    uint256 excessLong1Amount;
    uint256 excessShortAmount;
    if (cache.isShortExcess) excessShortAmount = shortAmountMinted.unsafeSub(param.shortAmount);
    else {
      excessLong0Amount = cache.token0Amount;
      excessLong1Amount = cache.token1Amount;

      if (param.long0Amount != 0) excessLong0Amount = excessLong0Amount.unsafeSub(param.long0Amount);

      if (param.long1Amount != 0) excessLong1Amount = excessLong1Amount.unsafeSub(param.long1Amount);
    }

    uint160 timeswapV2LiquidityAfter = ITimeswapV2Pool(msg.sender).totalLiquidity(param.strike, param.maturity);

    revert PassPoolMintCallbackInfo(
      param.liquidityAmount,
      excessLong0Amount,
      excessLong1Amount,
      excessShortAmount,
      timeswapV2LiquidityAfter,
      data
    );
  }

  /// @notice the abstract implementation for TimeswapV2OptionMintCallback
  /// @param param params for mintCallBack from TimeswapV2Option
  /// @return data data passed in bytes in the param passed back
  function timeswapV2OptionMintCallback(
    TimeswapV2OptionMintCallbackParam memory param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    uint256 liquidityAmount;
    (token0, token1, liquidityAmount, data) = abi.decode(param.data, (address, address, uint256, bytes));

    Verify.timeswapV2Option(optionFactory, token0, token1);

    data = timeswapV2PeripheryAddLiquidityGivenPrincipalInternal(
      TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam({
        optionPair: msg.sender,
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        token0Amount: param.token0AndLong0Amount,
        token1Amount: param.token1AndLong1Amount,
        liquidityAmount: liquidityAmount,
        data: data
      })
    );

    revert PassOptionMintCallbackInfo(param.shortAmount, data);
  }

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2AddLiquidity
  /// @notice will only be called if there is excess long
  /// @param param params for calling the implementation specfic addLiquidity to be overriden
  /// @return token0Amount amount of token0 to be deposited into the pool
  /// @return token1Amount amount of token1 to be deposited into the pool
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam memory param
  ) internal virtual returns (uint256 token0Amount, uint256 token1Amount, bytes memory data);

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2AddLiquidity
  /// @param param params for calling the implementation specfic addLiquidity to be overriden
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PeripheryAddLiquidityGivenPrincipalInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam memory param
  ) internal virtual returns (bytes memory data);
}

