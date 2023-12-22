// SPDX-License-Identifier: MIT
pragma solidity =0.8.8;

import {ERC1155Receiver} from "./ERC1155Receiver.sol";

import {Math} from "./Math.sol";
import {StrikeConversion} from "./StrikeConversion.sol";

import {CatchError} from "./CatchError.sol";

import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";

import {TimeswapV2OptionBurnParam} from "./structs_Param.sol";
import {TimeswapV2OptionBurnCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2OptionBurn} from "./enums_Transaction.sol";
import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2PoolFactory} from "./ITimeswapV2PoolFactory.sol";
import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PoolBurnParam, TimeswapV2PoolCollectTransactionFeesAndShortReturnedParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PoolBurnChoiceCallbackParam, TimeswapV2PoolBurnCallbackParam, TimeswapV2PoolAddFeesCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2PoolBurn} from "./enums_Transaction.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";

import {TimeswapV2TokenMintParam, TimeswapV2TokenBurnParam, TimeswapV2LiquidityTokenBurnParam, TimeswapV2LiquidityTokenCollectParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2TokenMintCallbackParam} from "./contracts_structs_CallbackParam.sol";
import {TimeswapV2LiquidityTokenPosition} from "./structs_Position.sol";

import {ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition} from "./ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition.sol";

import {TimeswapV2PeripheryRemoveLiquidityGivenPositionParam, FeesAndReturnedDelta, ExcessDelta} from "./structs_Param.sol";
import {TimeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternalParam, TimeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternalParam, TimeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternalParam} from "./InternalParam.sol";

import {Verify} from "./Verify.sol";

abstract contract TimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition is
  ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition,
  ERC1155Receiver
{
  using Math for uint256;
  using CatchError for bytes;

  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition
  address public immutable override poolFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition
  address public immutable override tokens;
  /// @inheritdoc ITimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition
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

  struct AmountFromPool {
    uint256 long0;
    uint256 long1;
    uint256 short;
  }

  /// @notice the abstract implementation for remove liquidity function
  /// @param param params for  removeLiquidity as mentioned in the TimeswapV2PeripheryRemoveLiquidityGivenPositionParam struct
  /// @param durationForward the amount of seconds moved forward
  /// @return token0Amount the resulting token0Amount
  /// @return token1Amount the resulting token1Amount
  /// @return feesAndReturnedDelta Delta of fees and short returned
  /// @return excessDelta Delta of excess position
  /// @return data data passed as bytes in the param
  /// @return timeswapV2LiquidityAfter the amount of liquidity after this transaction
  function removeLiquidityGivenPosition(
    TimeswapV2PeripheryRemoveLiquidityGivenPositionParam memory param,
    uint96 durationForward
  )
    internal
    returns (
      uint256 token0Amount,
      uint256 token1Amount,
      FeesAndReturnedDelta memory feesAndReturnedDelta,
      ExcessDelta memory excessDelta,
      bytes memory data,
      uint160 timeswapV2LiquidityAfter
    )
  {
    (address optionPair, address poolPair) = PoolFactoryLibrary.getWithCheck(
      optionFactory,
      poolFactory,
      param.token0,
      param.token1
    );

    timeswapV2LiquidityAfter = ITimeswapV2Pool(poolPair).totalLiquidity(param.strike, param.maturity);
    timeswapV2LiquidityAfter -= param.liquidityAmount;

    (
      feesAndReturnedDelta.long0Fees,
      feesAndReturnedDelta.long1Fees,
      feesAndReturnedDelta.shortFees,
      feesAndReturnedDelta.shortReturned
    ) = ITimeswapV2LiquidityToken(liquidityTokens).feesEarnedAndShortReturnedOf(
      msg.sender,
      TimeswapV2LiquidityTokenPosition({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity
      }),
      durationForward
    );

    excessDelta.shortAmount = feesAndReturnedDelta.shortReturned;

    if (param.liquidityAmount != 0) {
      data = abi.encode(
        param.token0,
        param.token1,
        feesAndReturnedDelta.long0Fees + param.excessLong0Amount,
        feesAndReturnedDelta.long1Fees + param.excessLong1Amount,
        excessDelta.shortAmount + feesAndReturnedDelta.shortFees + param.excessShortAmount,
        param.data
      );

      AmountFromPool memory amountFromPool;
      try
        ITimeswapV2Pool(poolPair).burn(
          TimeswapV2PoolBurnParam({
            strike: param.strike,
            maturity: param.maturity,
            long0To: address(this),
            long1To: address(this),
            shortTo: address(this),
            transaction: TimeswapV2PoolBurn.GivenLiquidity,
            delta: param.liquidityAmount,
            data: data
          })
        )
      {} catch (bytes memory reason) {
        data = reason.catchError(PassPoolBurnCallbackInfo.selector);
        (amountFromPool.long0, amountFromPool.long1, amountFromPool.short, data) = abi.decode(
          data,
          (uint256, uint256, uint256, bytes)
        );
      }

      excessDelta.long0Amount += amountFromPool.long0;
      excessDelta.long1Amount += amountFromPool.long1;
      excessDelta.shortAmount += amountFromPool.short;

      (token0Amount, token1Amount, data) = abi.decode(data, (uint256, uint256, bytes));
    } else {
      uint256 tokenAmountWithdraw = (excessDelta.shortAmount + feesAndReturnedDelta.shortFees + param.excessShortAmount)
        .min(
          StrikeConversion.combine(
            feesAndReturnedDelta.long0Fees + param.excessLong0Amount,
            feesAndReturnedDelta.long1Fees + param.excessLong1Amount,
            param.strike,
            true
          )
        );

      (token0Amount, token1Amount, data) = timeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternal(
        TimeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternalParam({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity,
          excessToken0Amount: feesAndReturnedDelta.long0Fees + param.excessLong0Amount,
          excessToken1Amount: feesAndReturnedDelta.long1Fees + param.excessLong1Amount,
          tokenAmountWithdraw: tokenAmountWithdraw,
          data: param.data
        })
      );
    }

    if (token0Amount != 0 || token1Amount != 0) {
      data = abi.encode(param.token0, param.token1, msg.sender, feesAndReturnedDelta, excessDelta, data);

      try
        ITimeswapV2Option(optionPair).burn(
          TimeswapV2OptionBurnParam({
            strike: param.strike,
            maturity: param.maturity,
            token0To: param.token0To,
            token1To: param.token1To,
            transaction: TimeswapV2OptionBurn.GivenTokensAndLongs,
            amount0: token0Amount,
            amount1: token1Amount,
            data: data
          })
        )
      {} catch (bytes memory reason) {
        data = reason.catchError(PassOptionBurnCallbackInfo.selector);
        data = abi.decode(data, (bytes));
      }

      (feesAndReturnedDelta, excessDelta, data) = abi.decode(data, (FeesAndReturnedDelta, ExcessDelta, bytes));
    }
    if (
      !(excessDelta.isRemoveLong0 || excessDelta.long0Amount == 0) ||
      !(excessDelta.isRemoveLong1 || excessDelta.long1Amount == 0) ||
      !(excessDelta.isRemoveShort || excessDelta.shortAmount == 0)
    )
      try
        ITimeswapV2Token(tokens).mint(
          TimeswapV2TokenMintParam({
            token0: param.token0,
            token1: param.token1,
            strike: param.strike,
            maturity: param.maturity,
            long0To: msg.sender,
            long1To: msg.sender,
            shortTo: msg.sender,
            long0Amount: excessDelta.isRemoveLong0 ? 0 : excessDelta.long0Amount,
            long1Amount: excessDelta.isRemoveLong1 ? 0 : excessDelta.long1Amount,
            shortAmount: excessDelta.isRemoveShort ? 0 : excessDelta.shortAmount,
            data: data
          })
        )
      {} catch (bytes memory reason) {
        reason.catchError(PassTokenMintCallbackInfo.selector);
      }
  }

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2PoolBurnChoiceCallback
  /// @param param params for calling the implementation specfic poolBurnChoiceCallback to be overriden
  /// @return long0Amount resulting long0 amount
  /// @return long1Amount resulting long1 amount
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PoolBurnChoiceCallback(
    TimeswapV2PoolBurnChoiceCallbackParam calldata param
  ) external returns (uint256 long0Amount, uint256 long1Amount, bytes memory data) {
    address token0;
    address token1;
    uint256 excessLong0Amount;
    uint256 excessLong1Amount;
    uint256 excessShortAmount;
    (token0, token1, excessLong0Amount, excessLong1Amount, excessShortAmount, data) = abi.decode(
      param.data,
      (address, address, uint256, uint256, uint256, bytes)
    );

    Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    uint256 token0AmountWithdraw;
    uint256 token1AmountWithdraw;

    uint256 tokenAmountWithdraw = (param.shortAmount + excessShortAmount).min(
      param.longAmount + StrikeConversion.combine(excessLong0Amount, excessLong1Amount, param.strike, true)
    );

    (
      long0Amount,
      long1Amount,
      token0AmountWithdraw,
      token1AmountWithdraw,
      data
    ) = timeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternal(
      TimeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternalParam({
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        token0Balance: param.long0Balance,
        token1Balance: param.long1Balance,
        excessToken0Amount: excessLong0Amount,
        excessToken1Amount: excessLong1Amount,
        tokenAmountFromPool: param.longAmount,
        tokenAmountWithdraw: tokenAmountWithdraw,
        data: data
      })
    );

    data = abi.encode(token0AmountWithdraw, token1AmountWithdraw, data);
  }

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2PoolBurnCallback
  /// @param param params for calling the implementation specfic poolBurnCallback to be overriden
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PoolBurnCallback(
    TimeswapV2PoolBurnCallbackParam calldata param
  ) external pure override returns (bytes memory data) {
    data = param.data;

    revert PassPoolBurnCallbackInfo(param.long0Amount, param.long1Amount, param.shortAmount, data);
  }

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2OptionBurnCallback
  /// @param param params for calling the implementation specfic optionBurnCallback to be overriden
  /// @return data data passed in bytes in the param passed back
  function timeswapV2OptionBurnCallback(
    TimeswapV2OptionBurnCallbackParam calldata param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    address msgSender;
    FeesAndReturnedDelta memory feesAndReturnedDelta;
    ExcessDelta memory excessDelta;
    (token0, token1, msgSender, feesAndReturnedDelta, excessDelta, data) = abi.decode(
      param.data,
      (address, address, address, FeesAndReturnedDelta, ExcessDelta, bytes)
    );

    Verify.timeswapV2Option(optionFactory, token0, token1);

    if (param.token0AndLong0Amount < feesAndReturnedDelta.long0Fees)
      feesAndReturnedDelta.long0Fees -= param.token0AndLong0Amount;
    else {
      uint256 remainingToken0AndLong0Amount = param.token0AndLong0Amount - feesAndReturnedDelta.long0Fees;
      excessDelta.isRemoveLong0 = remainingToken0AndLong0Amount > excessDelta.long0Amount;
      if (excessDelta.isRemoveLong0) excessDelta.long0Amount = remainingToken0AndLong0Amount - excessDelta.long0Amount;
      else excessDelta.long0Amount -= remainingToken0AndLong0Amount;
    }

    if (param.token1AndLong1Amount < feesAndReturnedDelta.long1Fees)
      feesAndReturnedDelta.long1Fees -= param.token1AndLong1Amount;
    else {
      uint256 remainingToken1AndLong1Amount = param.token1AndLong1Amount - feesAndReturnedDelta.long1Fees;
      excessDelta.isRemoveLong1 = remainingToken1AndLong1Amount > excessDelta.long1Amount;
      if (excessDelta.isRemoveLong1) excessDelta.long1Amount = remainingToken1AndLong1Amount - excessDelta.long1Amount;
      else excessDelta.long1Amount -= remainingToken1AndLong1Amount;
    }

    if (param.shortAmount < feesAndReturnedDelta.shortFees) feesAndReturnedDelta.shortFees -= param.shortAmount;
    else {
      uint256 remainingShortAmount = param.shortAmount - feesAndReturnedDelta.shortFees;
      excessDelta.isRemoveShort = remainingShortAmount > excessDelta.shortAmount;
      if (excessDelta.isRemoveShort) excessDelta.shortAmount = remainingShortAmount - excessDelta.shortAmount;
      else excessDelta.shortAmount -= remainingShortAmount;
    }

    if (excessDelta.isRemoveLong0 || excessDelta.isRemoveLong1 || excessDelta.isRemoveShort) {
      data = timeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternal(
        TimeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternalParam({
          token0: token0,
          token1: token1,
          strike: param.strike,
          maturity: param.maturity,
          excessLong0Amount: excessDelta.isRemoveLong0 ? excessDelta.long0Amount : 0,
          excessLong1Amount: excessDelta.isRemoveLong1 ? excessDelta.long1Amount : 0,
          excessShortAmount: excessDelta.isRemoveShort ? excessDelta.shortAmount : 0,
          data: data
        })
      );
    }

    data = abi.encode(feesAndReturnedDelta, excessDelta, data);

    revert PassOptionBurnCallbackInfo(data);
  }

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2TokenMintCallback
  /// @return data data passed in bytes in the param passed back
  function timeswapV2TokenMintCallback(
    TimeswapV2TokenMintCallbackParam calldata
  ) external view returns (bytes memory data) {
    Verify.timeswapV2Token(tokens);

    data = bytes("");

    revert PassTokenMintCallbackInfo();
  }

  /// @notice the virtual function which is to be implemented by the contract that inherits this contract
  /// @param param params for calling the this virtual function
  /// @return token0AmountFromPool The amount of token0 to be withdrawn from the pool
  /// @return token1AmountFromPool The amount of token1 to be withdrawn from the pool
  /// @return token0AmountWithdraw The amount of token0 to be withdrawn to receiver
  /// @return token1AmountWithdraw The amount of token1 to be withdrawn to receiver
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternal(
    TimeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternalParam memory param
  )
    internal
    virtual
    returns (
      uint256 token0AmountFromPool,
      uint256 token1AmountFromPool,
      uint256 token0AmountWithdraw,
      uint256 token1AmountWithdraw,
      bytes memory data
    );

  /// @notice the virtual function which is to be implemented by the contract that inherits this contract
  /// @param param params for calling the this virtual function
  /// @return token0AmountWithdraw The amount of token0 to be withdrawn to receiver
  /// @return token1AmountWithdraw The amount of token1 to be withdrawn to receiver
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternal(
    TimeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternalParam memory param
  ) internal virtual returns (uint256 token0AmountWithdraw, uint256 token1AmountWithdraw, bytes memory data);

  /// @notice the virtual function which is to be implemented by the contract that inherits this contract
  /// @dev This is where the position must be transferred
  /// @param param params for calling the this virtual function
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternal(
    TimeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternalParam memory param
  ) internal virtual returns (bytes memory data);
}

