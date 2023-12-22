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

import {TimeswapV2PoolMintParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PoolMintChoiceCallbackParam, TimeswapV2PoolMintCallbackParam, TimeswapV2PoolAddFeesCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2PoolMint} from "./enums_Transaction.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenMintParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2TokenMintCallbackParam} from "./contracts_structs_CallbackParam.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";

import {TimeswapV2LiquidityTokenMintParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2LiquidityTokenMintCallbackParam} from "./contracts_structs_CallbackParam.sol";

import {ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam, TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam} from "./InternalParam.sol";

import {Verify} from "./Verify.sol";

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
  address public immutable override tokens;
  /// @inheritdoc ITimeswapV2PeripheryQuoterAddLiquidityGivenPrincipal
  address public immutable override liquidityTokens;

  /* ===== INIT ===== */

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenLiquidityTokens
  ) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
    tokens = chosenTokens;
    liquidityTokens = chosenLiquidityTokens;
  }

  /// @notice the abstract implementation for addLiquidity function
  /// @param param params for  addLiquidity as mentioned in the TimeswapV2PeripheryAddLiquidityGivenPrincipalParam struct
  /// @param durationForward the amount of seconds moved forward
  /// @return liquidityAmount amount of liquidity in the pool
  /// @return excessLong0Amount amount os excessLong0Amount while liquidity was minted if any
  /// @return excessLong1Amount amount os excessLong1Amount while liquidity was minted if any
  /// @return excessShortAmount amount os shortAmount while liquidity was minted if any
  /// @return data data passed as bytes in the param
  /// @return timeswapV2LiquidityAfter the amount of liquidity after this transaction
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
      (liquidityAmount, timeswapV2LiquidityAfter, data) = abi.decode(data, (uint160, uint160, bytes));
    }

    (excessLong0Amount, excessLong1Amount, excessShortAmount, data) = abi.decode(
      data,
      (uint256, uint256, uint256, bytes)
    );

    try
      ITimeswapV2LiquidityToken(liquidityTokens).mint(
        TimeswapV2LiquidityTokenMintParam({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity,
          to: param.liquidityTo,
          liquidityAmount: liquidityAmount,
          data: bytes(""),
          erc1155Data: param.erc1155Data
        })
      )
    {} catch (bytes memory reason) {
      reason.catchError(PassLiquidityTokenMintCallbackInfo.selector);
    }

    if (excessLong0Amount != 0 || excessLong1Amount != 0 || excessShortAmount != 0)
      try
        ITimeswapV2Token(tokens).mint(
          TimeswapV2TokenMintParam({
            token0: param.token0,
            token1: param.token1,
            strike: param.strike,
            maturity: param.maturity,
            long0To: param.liquidityTo,
            long1To: param.liquidityTo,
            shortTo: param.liquidityTo,
            long0Amount: excessLong0Amount,
            long1Amount: excessLong1Amount,
            shortAmount: excessShortAmount,
            data: bytes("")
          })
        )
      {} catch (bytes memory reason) {
        reason.catchError(PassTokenMintCallbackInfo.selector);
      }
  }

  /// @notice the abstract implementation for TimeswapV2PoolMintChoiceCallback
  /// @param param params for mintChoiceCallBack from TimeswapV2Pool
  /// @return long0Amount long0AMount chosen to be minted
  /// @return long1Amount chosen to be minted
  /// @return data data passed in bytes in the param passed back
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

    bool isShortExcess = param.shortAmount < param.longAmount;
    if (isShortExcess) {
      long0Amount = token0Amount;
      long1Amount = token1Amount;
    } else {
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
    }

    data = abi.encode(
      CacheForTimeswapV2PoolMintCallback(token0, token1, isShortExcess, token0Amount, token1Amount),
      data
    );
  }

  struct CacheForTimeswapV2PoolMintCallback {
    address token0;
    address token1;
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

    data = abi.encode(excessLong0Amount, excessLong1Amount, excessShortAmount, data);

    uint160 timeswapV2LiquidityAfter = ITimeswapV2Pool(msg.sender).totalLiquidity(param.strike, param.maturity);

    revert PassPoolMintCallbackInfo(param.liquidityAmount, timeswapV2LiquidityAfter, data);
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

  /// @notice the abstract implementation for TimeswapV2LiquidityTokenMintCallback
  function timeswapV2LiquidityTokenMintCallback(
    TimeswapV2LiquidityTokenMintCallbackParam calldata
  ) external view override returns (bytes memory) {
    Verify.timeswapV2LiquidityToken(liquidityTokens);

    revert PassLiquidityTokenMintCallbackInfo();
  }

  /// @notice the abstract implementation for TimeswapV2TokenMintCallback
  function timeswapV2TokenMintCallback(TimeswapV2TokenMintCallbackParam calldata) external view returns (bytes memory) {
    Verify.timeswapV2Token(tokens);

    revert PassTokenMintCallbackInfo();
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

