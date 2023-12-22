// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {CatchError} from "./CatchError.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";
import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {TimeswapV2OptionCollectCallbackParam} from "./CallbackParam.sol";
import {TimeswapV2OptionCollectParam} from "./structs_Param.sol";

import {TimeswapV2OptionCollect} from "./Transaction.sol";

import {TimeswapV2PeripheryShortAfterMaturityParam} from "./structs_Param.sol";

import {ITimeswapV2PeripheryQuoterShortAfterMaturity} from "./ITimeswapV2PeripheryQuoterShortAfterMaturity.sol";
import {Verify} from "./Verify.sol";

abstract contract TimeswapV2PeripheryQuoterShortAfterMaturity is ITimeswapV2PeripheryQuoterShortAfterMaturity {
  using CatchError for bytes;

  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryQuoterShortAfterMaturity
  address public immutable override optionFactory;

  /* ===== INIT ===== */

  constructor(address chosenOptionFactory) {
    optionFactory = chosenOptionFactory;
  }

  /// @notice the abstract implementation for short after maturity function
  /// @param param params for short breakdown
  /// @return token0Amount is the token0Amount recieved
  /// @return token1Amount is the token0Amount recieved
  function shortAfterMaturity(
    TimeswapV2PeripheryShortAfterMaturityParam memory param
  ) internal returns (uint256 token0Amount, uint256 token1Amount) {
    address optionPair = OptionFactoryLibrary.getWithCheck(optionFactory, param.token0, param.token1);

    try
      ITimeswapV2Option(optionPair).collect(
        TimeswapV2OptionCollectParam({
          strike: param.strike,
          maturity: param.maturity,
          token0To: param.token0To,
          token1To: param.token1To,
          transaction: TimeswapV2OptionCollect.GivenShort,
          amount: param.positionAmount,
          data: bytes("0")
        })
      )
    {} catch (bytes memory reason) {
      bytes memory data = reason.catchError(PassOptionCollectCallbackInfo.selector);
      (token0Amount, token1Amount) = abi.decode(data, (uint256, uint256));
    }
  }

  function timeswapV2OptionCollectCallback(
    TimeswapV2OptionCollectCallbackParam calldata param
  ) external override returns (bytes memory data) {
    data = bytes("");

    revert PassOptionCollectCallbackInfo(param.token0Amount, param.token1Amount);
  }
}

