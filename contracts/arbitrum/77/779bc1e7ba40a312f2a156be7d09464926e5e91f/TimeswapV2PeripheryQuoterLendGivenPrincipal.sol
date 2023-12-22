// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {StrikeConversion} from "./StrikeConversion.sol";
import {CatchError} from "./CatchError.sol";

import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";
import {TimeswapV2OptionMintParam} from "./structs_Param.sol";
import {TimeswapV2OptionMintCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2OptionMint} from "./enums_Transaction.sol";
import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PoolDeleverageParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PoolDeleverageChoiceCallbackParam, TimeswapV2PoolDeleverageCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2PoolDeleverage} from "./enums_Transaction.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenMintParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2TokenMintCallbackParam} from "./contracts_structs_CallbackParam.sol";

import {ITimeswapV2PeripheryQuoterLendGivenPrincipal} from "./ITimeswapV2PeripheryQuoterLendGivenPrincipal.sol";

import {TimeswapV2PeripheryLendGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryLendGivenPrincipalInternalParam} from "./InternalParam.sol";

import {Verify} from "./libraries_Verify.sol";

abstract contract TimeswapV2PeripheryQuoterLendGivenPrincipal is ITimeswapV2PeripheryQuoterLendGivenPrincipal {
  using CatchError for bytes;

  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryQuoterLendGivenPrincipal
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterLendGivenPrincipal
  address public immutable override poolFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterLendGivenPrincipal
  address public immutable override tokens;

  /* ===== INIT ===== */

  constructor(address chosenOptionFactory, address chosenPoolFactory, address chosenTokens) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
    tokens = chosenTokens;
  }

  function lendGivenPrincipal(
    TimeswapV2PeripheryLendGivenPrincipalParam memory param,
    uint96 durationForward
  ) internal returns (uint256 positionAmount, bytes memory data, uint160 timeswapV2SqrtInterestRateAfter) {
    (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

    data = abi.encode(param.token0, param.token1, param.to, param.token0Amount, param.token1Amount, param.data);

    try
      ITimeswapV2Pool(poolPair).deleverage(
        TimeswapV2PoolDeleverageParam({
          strike: param.strike,
          maturity: param.maturity,
          to: address(this),
          transaction: TimeswapV2PoolDeleverage.GivenLong,
          delta: StrikeConversion.combine(param.token0Amount, param.token1Amount, param.strike, false),
          data: data
        }),
        durationForward
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassPoolDeleverageCallbackInfo.selector);
      (timeswapV2SqrtInterestRateAfter, data) = abi.decode(data, (uint160, bytes));
    }

    (positionAmount, data) = abi.decode(data, (uint256, bytes));
  }

  function timeswapV2PoolDeleverageChoiceCallback(
    TimeswapV2PoolDeleverageChoiceCallbackParam calldata param
  ) external view override returns (uint256 long0Amount, uint256 long1Amount, bytes memory data) {
    address token0;
    address token1;
    address to;
    (token0, token1, to, long0Amount, long1Amount, data) = abi.decode(
      param.data,
      (address, address, address, uint256, uint256, bytes)
    );

    Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    data = abi.encode(token0, token1, to, data);
  }

  function timeswapV2PoolDeleverageCallback(
    TimeswapV2PoolDeleverageCallbackParam calldata param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    address to;
    (token0, token1, to, data) = abi.decode(param.data, (address, address, address, bytes));

    address optionPair = Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    data = abi.encode(token0, token1, to, param.shortAmount, data);

    try
      ITimeswapV2Option(optionPair).mint(
        TimeswapV2OptionMintParam({
          strike: param.strike,
          maturity: param.maturity,
          long0To: msg.sender,
          long1To: msg.sender,
          shortTo: address(this),
          transaction: TimeswapV2OptionMint.GivenTokensAndLongs,
          amount0: param.long0Amount,
          amount1: param.long1Amount,
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

    revert PassPoolDeleverageCallbackInfo(timeswapV2SqrtInterestRateAfter, data);
  }

  function timeswapV2OptionMintCallback(
    TimeswapV2OptionMintCallbackParam memory param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    address to;
    uint256 shortAmount;
    (token0, token1, to, shortAmount, data) = abi.decode(param.data, (address, address, address, uint256, bytes));

    Verify.timeswapV2Option(optionFactory, token0, token1);

    shortAmount += param.shortAmount;

    ITimeswapV2Token(tokens).mint(
      TimeswapV2TokenMintParam({
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        long0To: address(this),
        long1To: address(this),
        shortTo: to,
        long0Amount: 0,
        long1Amount: 0,
        shortAmount: shortAmount,
        data: bytes("")
      })
    );

    data = timeswapV2PeripheryLendGivenPrincipalInternal(
      TimeswapV2PeripheryLendGivenPrincipalInternalParam({
        optionPair: msg.sender,
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        token0Amount: param.token0AndLong0Amount,
        token1Amount: param.token1AndLong1Amount,
        positionAmount: shortAmount,
        data: data
      })
    );

    data = abi.encode(shortAmount, data);

    revert PassOptionMintCallbackInfo(data);
  }

  function timeswapV2TokenMintCallback(
    TimeswapV2TokenMintCallbackParam calldata param
  ) external returns (bytes memory data) {
    Verify.timeswapV2Token(tokens);

    address optionPair = OptionFactoryLibrary.get(optionFactory, param.token0, param.token1);

    ITimeswapV2Option(optionPair).transferPosition(
      param.strike,
      param.maturity,
      msg.sender,
      TimeswapV2OptionPosition.Short,
      param.shortAmount
    );

    data = bytes("");
  }

  function timeswapV2PeripheryLendGivenPrincipalInternal(
    TimeswapV2PeripheryLendGivenPrincipalInternalParam memory param
  ) internal virtual returns (bytes memory data);
}

