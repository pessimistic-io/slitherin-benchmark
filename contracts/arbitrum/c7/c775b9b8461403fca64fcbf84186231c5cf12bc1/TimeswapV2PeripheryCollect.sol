// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ERC1155Receiver} from "./ERC1155Receiver.sol";

import {ITimeswapV2OptionFactory} from "./ITimeswapV2OptionFactory.sol";
import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";

import {TimeswapV2OptionCollectParam} from "./structs_Param.sol";

import {TimeswapV2OptionCollect} from "./Transaction.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenBurnParam} from "./v2-token_contracts_structs_Param.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";
import {TimeswapV2LiquidityTokenPosition} from "./structs_Position.sol";

import {TimeswapV2TokenBurnParam, TimeswapV2LiquidityTokenCollectParam} from "./v2-token_contracts_structs_Param.sol";

import {TimeswapV2PeripheryCollectParam} from "./structs_Param.sol";

import {ITimeswapV2PeripheryCollect} from "./ITimeswapV2PeripheryCollect.sol";

abstract contract TimeswapV2PeripheryCollect is ITimeswapV2PeripheryCollect, ERC1155Receiver {
  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryCollect
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryCollect
  address public immutable override tokens;
  /// @inheritdoc ITimeswapV2PeripheryCollect
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
    // Get the amount of short fees and short returned the msg.sender has
    (, , uint256 shortFees, uint256 shortReturned) = ITimeswapV2LiquidityToken(liquidityTokens)
      .feesEarnedAndShortReturnedOf(
        msg.sender,
        TimeswapV2LiquidityTokenPosition({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity
        })
      );

    uint256 shortAmount;

    // Include the short fees and short returned to the total amount of short to burn and withdraw the base ERC20
    if (shortFees != 0 || shortReturned != 0) {
      uint256 shortReturnedAmount;

      (, , shortAmount, shortReturnedAmount, ) = ITimeswapV2LiquidityToken(liquidityTokens).collect(
        TimeswapV2LiquidityTokenCollectParam({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity,
          from: msg.sender,
          long0FeesTo: address(this),
          long1FeesTo: address(this),
          shortFeesTo: address(this),
          shortReturnedTo: address(this),
          long0FeesDesired: 0,
          long1FeesDesired: 0,
          shortFeesDesired: type(uint256).max,
          shortReturnedDesired: type(uint256).max,
          data: bytes("")
        })
      );
      shortAmount += shortReturnedAmount;
    }

    // If there is any excess short amount, unwrap it first to get the short position
    if (param.excessShortAmount != 0) {
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
          data: bytes("")
        })
      );

      shortAmount += param.excessShortAmount;
    }

    address optionPair = OptionFactoryLibrary.getWithCheck(optionFactory, param.token0, param.token1);

    // Collect the underlying ERC20 token by burning the short total
    (token0Amount, token1Amount, , ) = ITimeswapV2Option(optionPair).collect(
      TimeswapV2OptionCollectParam({
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.token0To,
        token1To: param.token1To,
        transaction: TimeswapV2OptionCollect.GivenShort,
        amount: shortAmount,
        data: bytes("")
      })
    );
  }
}

