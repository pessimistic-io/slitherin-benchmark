// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ERC1155Receiver} from "./ERC1155Receiver.sol";

import {CatchError} from "./CatchError.sol";

import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {TimeswapV2OptionCollect} from "./Transaction.sol";

import {TimeswapV2OptionCollectParam} from "./structs_Param.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";
import {TimeswapV2TokenBurnParam, TimeswapV2LiquidityTokenCollectParam} from "./contracts_structs_Param.sol";
import {TimeswapV2TokenBurnCallbackParam} from "./structs_CallbackParam.sol";
import {TimeswapV2OptionCollectCallbackParam} from "./structs_CallbackParam.sol";
import {TimeswapV2LiquidityTokenPosition} from "./structs_Position.sol";

import {TimeswapV2PeripheryCollectParam} from "./structs_Param.sol";

import {ITimeswapV2PeripheryQuoterCollect} from "./ITimeswapV2PeripheryQuoterCollect.sol";

/// @title Abstract contract which specifies functions that are required for collect which are to be inherited for a specific DEX/Aggregator implementation
abstract contract TimeswapV2PeripheryQuoterCollect is ITimeswapV2PeripheryQuoterCollect, ERC1155Receiver {
  using CatchError for bytes;

  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryQuoterCollect
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterCollect
  address public immutable override tokens;
  /// @inheritdoc ITimeswapV2PeripheryQuoterCollect
  address public immutable override liquidityTokens;

  /* ===== INIT ===== */

  constructor(address chosenOptionFactory, address chosenTokens, address chosenLiquidityTokens) {
    optionFactory = chosenOptionFactory;
    tokens = chosenTokens;
    liquidityTokens = chosenLiquidityTokens;
  }

  /// @notice the abstract implementation for collect function
  /// @param param for collect as mentioned in the TimeswapV2PeripheryCollectParam struct
  /// @return token0Amount is the token0Amount recieved
  /// @return token1Amount is the token1Amount recieved
  function collect(
    TimeswapV2PeripheryCollectParam memory param
  ) internal returns (uint256 token0Amount, uint256 token1Amount) {
    (, , uint256 shortAmount, uint256 shortReturnedAmount) = ITimeswapV2LiquidityToken(liquidityTokens)
      .feesEarnedAndShortReturnedOf(
        msg.sender,
        TimeswapV2LiquidityTokenPosition({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity
        })
      );

    shortAmount += shortReturnedAmount;

    bytes memory data;
    if (param.excessShortAmount != 0) {
      data = abi.encode(shortAmount);

      try
        ITimeswapV2Token(tokens).burn(
          TimeswapV2TokenBurnParam({
            token0: param.token0,
            token1: param.token1,
            strike: param.strike,
            maturity: param.maturity,
            long0To: address(this),
            long1To: address(this),
            shortTo: address(this),
            long0Amount: 0,
            long1Amount: 0,
            shortAmount: param.excessShortAmount,
            data: data
          })
        )
      {} catch (bytes memory reason) {
        data = reason.catchError(PassTokenBurnCallbackInfo.selector);
        (shortAmount) = abi.decode(data, (uint256));
      }
    }

    address optionPair = OptionFactoryLibrary.getWithCheck(optionFactory, param.token0, param.token1);

    try
      ITimeswapV2Option(optionPair).collect(
        TimeswapV2OptionCollectParam({
          strike: param.strike,
          maturity: param.maturity,
          token0To: param.token0To,
          token1To: param.token1To,
          transaction: TimeswapV2OptionCollect.GivenShort,
          amount: shortAmount,
          data: bytes("0")
        })
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassOptionCollectCallbackInfo.selector);
      (token0Amount, token1Amount) = abi.decode(data, (uint256, uint256));
    }
  }

  /// @notice the abstract implementation for token burn function
  /// @param param params for  timeswapV2TokenBurnCallback
  /// @return data data passed as bytes in the param
  function timeswapV2TokenBurnCallback(
    TimeswapV2TokenBurnCallbackParam calldata param
  ) external pure returns (bytes memory data) {
    uint256 shortAmount = abi.decode(param.data, (uint256));

    shortAmount += param.shortAmount;

    data = bytes("");

    revert PassTokenBurnCallbackInfo(shortAmount);
  }

  /// @notice the abstract implementation for option collect callback function
  /// @param param params for  timeswapV2OptionCollectCallback
  /// @return data data passed as bytes in the param
  function timeswapV2OptionCollectCallback(
    TimeswapV2OptionCollectCallbackParam calldata param
  ) external pure returns (bytes memory data) {
    data = bytes("");

    revert PassOptionCollectCallbackInfo(param.token0Amount, param.token1Amount);
  }
}

