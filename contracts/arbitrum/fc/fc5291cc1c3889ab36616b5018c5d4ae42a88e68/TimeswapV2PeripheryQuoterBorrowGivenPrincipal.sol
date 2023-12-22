// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {StrikeConversion} from "./StrikeConversion.sol";
import {CatchError} from "./CatchError.sol";

import {ITimeswapV2OptionFactory} from "./ITimeswapV2OptionFactory.sol";
import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";
import {TimeswapV2OptionMintParam, TimeswapV2OptionSwapParam} from "./structs_Param.sol";
import {TimeswapV2OptionMintCallbackParam, TimeswapV2OptionSwapCallbackParam} from "./structs_CallbackParam.sol";
import {TimeswapV2OptionSwap} from "./enums_Transaction.sol";
import {TimeswapV2OptionMint} from "./enums_Transaction.sol";
import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PoolLeverageParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PoolLeverageChoiceCallbackParam, TimeswapV2PoolLeverageCallbackParam} from "./structs_CallbackParam.sol";
import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {TimeswapV2PoolLeverage} from "./enums_Transaction.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenMintParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2TokenMintCallbackParam} from "./contracts_structs_CallbackParam.sol";

import {ITimeswapV2PeripheryQuoterBorrowGivenPrincipal} from "./ITimeswapV2PeripheryQuoterBorrowGivenPrincipal.sol";

import {TimeswapV2PeripheryBorrowGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryBorrowGivenPrincipalInternalParam} from "./InternalParam.sol";

import {Verify} from "./Verify.sol";

abstract contract TimeswapV2PeripheryQuoterBorrowGivenPrincipal is ITimeswapV2PeripheryQuoterBorrowGivenPrincipal {
  using CatchError for bytes;

  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryQuoterBorrowGivenPrincipal
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterBorrowGivenPrincipal
  address public immutable override poolFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterBorrowGivenPrincipal
  address public immutable override tokens;
  ///@dev data recieved from optionMintCallback
  struct CacheForTimeswapV2OptionMintCallback {
    address token0;
    address token1;
    address tokenTo;
    address longTo;
    bool isLong0;
    uint256 swapAmount;
    uint256 positionAmount;
  }

  /* ===== INIT ===== */

  constructor(address chosenOptionFactory, address chosenPoolFactory, address chosenTokens) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
    tokens = chosenTokens;
  }

  function borrowGivenPrincipal(
    TimeswapV2PeripheryBorrowGivenPrincipalParam memory param,
    uint96 durationForward
  ) internal returns (uint256 positionAmount, bytes memory data, uint160 timeswapV2SqrtInterestRateAfter) {
    (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

    data = abi.encode(
      param.token0,
      param.token1,
      param.tokenTo,
      param.longTo,
      param.isLong0,
      param.token0Amount,
      param.token1Amount,
      param.data
    );

    try
      ITimeswapV2Pool(poolPair).leverage(
        TimeswapV2PoolLeverageParam({
          strike: param.strike,
          maturity: param.maturity,
          long0To: address(this),
          long1To: address(this),
          transaction: TimeswapV2PoolLeverage.GivenLong,
          delta: StrikeConversion.combine(param.token0Amount, param.token1Amount, param.strike, true),
          data: data
        }),
        durationForward
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassPoolLeverageCallbackInfo.selector);
      (timeswapV2SqrtInterestRateAfter, data) = abi.decode(data, (uint160, bytes));
    }

    (positionAmount, data) = abi.decode(data, (uint256, bytes));
  }

  function timeswapV2PoolLeverageChoiceCallback(
    TimeswapV2PoolLeverageChoiceCallbackParam calldata param
  ) external view override returns (uint256 long0Amount, uint256 long1Amount, bytes memory data) {
    address token0;
    address token1;
    address tokenTo;
    address longTo;
    bool isLong0;
    (token0, token1, tokenTo, longTo, isLong0, long0Amount, long1Amount, data) = abi.decode(
      param.data,
      (address, address, address, address, bool, uint256, uint256, bytes)
    );

    Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    data = abi.encode(token0, token1, tokenTo, longTo, isLong0, data);
  }

  function timeswapV2PoolLeverageCallback(
    TimeswapV2PoolLeverageCallbackParam calldata param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    address tokenTo;
    address longTo;
    bool isLong0;
    (token0, token1, tokenTo, longTo, isLong0, data) = abi.decode(
      param.data,
      (address, address, address, address, bool, bytes)
    );

    address optionPair = Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    data = abi.encode(
      CacheForTimeswapV2OptionMintCallback(
        token0,
        token1,
        tokenTo,
        longTo,
        isLong0,
        isLong0 ? param.long1Amount : param.long0Amount,
        isLong0 ? param.long0Amount : param.long1Amount
      ),
      data
    );

    try
      ITimeswapV2Option(optionPair).mint(
        TimeswapV2OptionMintParam({
          strike: param.strike,
          maturity: param.maturity,
          long0To: address(this),
          long1To: address(this),
          shortTo: msg.sender,
          transaction: TimeswapV2OptionMint.GivenShorts,
          amount0: isLong0 ? param.shortAmount : 0,
          amount1: isLong0 ? 0 : param.shortAmount,
          data: data
        })
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassOptionMintCallbackInfo.selector);
      data = abi.decode(data, (bytes));
    }

    uint160 timeswapV2SqrtInterestRateAfter = ITimeswapV2Pool(msg.sender).sqrtInterestRate(
      param.strike,
      param.maturity
    );

    revert PassPoolLeverageCallbackInfo(timeswapV2SqrtInterestRateAfter, data);
  }

  function timeswapV2OptionMintCallback(
    TimeswapV2OptionMintCallbackParam memory param
  ) external override returns (bytes memory data) {
    CacheForTimeswapV2OptionMintCallback memory cache;
    (cache, data) = abi.decode(param.data, (CacheForTimeswapV2OptionMintCallback, bytes));

    Verify.timeswapV2Option(optionFactory, cache.token0, cache.token1);

    cache.positionAmount += cache.isLong0 ? param.token0AndLong0Amount : param.token1AndLong1Amount;

    if (cache.swapAmount != 0) {
      data = abi.encode(
        cache.token0,
        cache.token1,
        cache.longTo,
        cache.isLong0 ? param.token0AndLong0Amount : param.token1AndLong1Amount,
        cache.positionAmount,
        data
      );

      try
        ITimeswapV2Option(msg.sender).swap(
          TimeswapV2OptionSwapParam({
            strike: param.strike,
            maturity: param.maturity,
            tokenTo: cache.tokenTo,
            longTo: address(this),
            isLong0ToLong1: !cache.isLong0,
            transaction: cache.isLong0
              ? TimeswapV2OptionSwap.GivenToken1AndLong1
              : TimeswapV2OptionSwap.GivenToken0AndLong0,
            amount: cache.swapAmount,
            data: data
          })
        )
      {} catch (bytes memory reason) {
        data = reason.catchError(PassOptionSwapCallbackInfo.selector);
        data = abi.decode(data, (bytes));
      }
    } else {
      ITimeswapV2Token(tokens).mint(
        TimeswapV2TokenMintParam({
          token0: cache.token0,
          token1: cache.token1,
          strike: param.strike,
          maturity: param.maturity,
          long0To: cache.isLong0 ? cache.longTo : address(this),
          long1To: cache.isLong0 ? address(this) : cache.longTo,
          shortTo: address(this),
          long0Amount: cache.isLong0 ? cache.positionAmount : 0,
          long1Amount: cache.isLong0 ? 0 : cache.positionAmount,
          shortAmount: 0,
          data: bytes("")
        })
      );

      data = timeswapV2PeripheryBorrowGivenPrincipalInternal(
        TimeswapV2PeripheryBorrowGivenPrincipalInternalParam({
          optionPair: msg.sender,
          token0: cache.token0,
          token1: cache.token1,
          strike: param.strike,
          maturity: param.maturity,
          isLong0: cache.isLong0,
          token0Amount: cache.isLong0 ? param.token0AndLong0Amount : 0,
          token1Amount: cache.isLong0 ? 0 : param.token1AndLong1Amount,
          positionAmount: cache.positionAmount,
          data: data
        })
      );

      data = abi.encode(cache.positionAmount, data);
    }

    revert PassOptionMintCallbackInfo(data);
  }

  function timeswapV2OptionSwapCallback(
    TimeswapV2OptionSwapCallbackParam calldata param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    address longTo;
    uint256 depositAmount;
    uint256 positionAmount;
    (token0, token1, longTo, depositAmount, positionAmount, data) = abi.decode(
      param.data,
      (address, address, address, uint256, uint256, bytes)
    );

    Verify.timeswapV2Option(optionFactory, token0, token1);

    positionAmount += param.isLong0ToLong1 ? param.token1AndLong1Amount : param.token0AndLong0Amount;

    ITimeswapV2Token(tokens).mint(
      TimeswapV2TokenMintParam({
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        long0To: param.isLong0ToLong1 ? address(this) : longTo,
        long1To: param.isLong0ToLong1 ? longTo : address(this),
        shortTo: address(this),
        long0Amount: param.isLong0ToLong1 ? 0 : positionAmount,
        long1Amount: param.isLong0ToLong1 ? positionAmount : 0,
        shortAmount: 0,
        data: bytes("")
      })
    );

    data = timeswapV2PeripheryBorrowGivenPrincipalInternal(
      TimeswapV2PeripheryBorrowGivenPrincipalInternalParam({
        optionPair: msg.sender,
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        isLong0: !param.isLong0ToLong1,
        token0Amount: param.token0AndLong0Amount + (param.isLong0ToLong1 ? 0 : depositAmount),
        token1Amount: param.token1AndLong1Amount + (param.isLong0ToLong1 ? depositAmount : 0),
        positionAmount: positionAmount,
        data: data
      })
    );

    data = abi.encode(positionAmount, data);

    revert PassOptionSwapCallbackInfo(data);
  }

  function timeswapV2TokenMintCallback(
    TimeswapV2TokenMintCallbackParam calldata param
  ) external override returns (bytes memory data) {
    Verify.timeswapV2Token(tokens);

    address optionPair = OptionFactoryLibrary.get(optionFactory, param.token0, param.token1);

    ITimeswapV2Option(optionPair).transferPosition(
      param.strike,
      param.maturity,
      msg.sender,
      param.long0Amount != 0 ? TimeswapV2OptionPosition.Long0 : TimeswapV2OptionPosition.Long1,
      param.long0Amount != 0 ? param.long0Amount : param.long1Amount
    );

    data = bytes("");
  }

  function timeswapV2PeripheryBorrowGivenPrincipalInternal(
    TimeswapV2PeripheryBorrowGivenPrincipalInternalParam memory param
  ) internal virtual returns (bytes memory data);
}

