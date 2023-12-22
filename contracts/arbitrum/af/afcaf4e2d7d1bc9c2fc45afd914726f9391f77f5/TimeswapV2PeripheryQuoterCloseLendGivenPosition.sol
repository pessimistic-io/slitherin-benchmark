// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ERC1155Receiver} from "./ERC1155Receiver.sol";

import {CatchError} from "./CatchError.sol";

import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {TimeswapV2OptionBurnParam} from "./structs_Param.sol";

import {TimeswapV2OptionMint, TimeswapV2OptionBurn, TimeswapV2OptionSwap} from "./enums_Transaction.sol";
import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {TimeswapV2PoolLeverageParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PoolLeverageChoiceCallbackParam, TimeswapV2PoolLeverageCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2PoolLeverage} from "./enums_Transaction.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenBurnParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2TokenBurnCallbackParam} from "./structs_CallbackParam.sol";

import {ITimeswapV2PeripheryQuoterCloseLendGivenPosition} from "./ITimeswapV2PeripheryQuoterCloseLendGivenPosition.sol";

import {TimeswapV2PeripheryCloseLendGivenPositionParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam} from "./InternalParam.sol";

import {Verify} from "./Verify.sol";

abstract contract TimeswapV2PeripheryQuoterCloseLendGivenPosition is
  ITimeswapV2PeripheryQuoterCloseLendGivenPosition,
  ERC1155Receiver
{
  using CatchError for bytes;

  /* ===== MODEL ===== */
  /// @inheritdoc ITimeswapV2PeripheryQuoterCloseLendGivenPosition
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterCloseLendGivenPosition
  address public immutable override poolFactory;
  /// @inheritdoc ITimeswapV2PeripheryQuoterCloseLendGivenPosition
  address public immutable override tokens;

  /* ===== INIT ===== */

  constructor(address chosenOptionFactory, address chosenPoolFactory, address chosenTokens) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
    tokens = chosenTokens;
  }

  function closeLendGivenPosition(
    TimeswapV2PeripheryCloseLendGivenPositionParam memory param,
    uint96 durationForward
  )
    internal
    returns (uint256 token0Amount, uint256 token1Amount, bytes memory data, uint160 timeswapV2SqrtInterestRateAfter)
  {
    data = abi.encode(param.token0To, param.token1To, param.positionAmount, durationForward, param.data);

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
          shortAmount: param.positionAmount,
          data: data
        })
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassTokenBurnCallbackInfo.selector);
      (timeswapV2SqrtInterestRateAfter, token0Amount, token1Amount, data) = abi.decode(
        data,
        (uint160, uint256, uint256, bytes)
      );
    }
  }

  function timeswapV2TokenBurnCallback(
    TimeswapV2TokenBurnCallbackParam calldata param
  ) external returns (bytes memory data) {
    address token0To;
    address token1To;
    uint256 positionAmount;
    uint96 durationForward;
    (token0To, token1To, positionAmount, durationForward, data) = abi.decode(
      param.data,
      (address, address, uint256, uint96, bytes)
    );

    (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

    data = abi.encode(param.token0, param.token1, token0To, token1To, positionAmount, data);

    try
      ITimeswapV2Pool(poolPair).leverage(
        TimeswapV2PoolLeverageParam({
          strike: param.strike,
          maturity: param.maturity,
          long0To: address(this),
          long1To: address(this),
          transaction: TimeswapV2PoolLeverage.GivenSum,
          delta: positionAmount,
          data: data
        }),
        durationForward
      )
    {} catch (bytes memory reason) {
      data = reason.catchError(PassPoolLeverageCallbackInfo.selector);

      uint160 timeswapV2SqrtInterestRateAfter;
      uint256 token0Amount;
      uint256 token1Amount;
      (timeswapV2SqrtInterestRateAfter, token0Amount, token1Amount, data) = abi.decode(
        data,
        (uint160, uint256, uint256, bytes)
      );

      revert PassTokenBurnCallbackInfo(timeswapV2SqrtInterestRateAfter, token0Amount, token1Amount, data);
    }
  }

  function timeswapV2PoolLeverageChoiceCallback(
    TimeswapV2PoolLeverageChoiceCallbackParam calldata param
  ) external override returns (uint256 long0Amount, uint256 long1Amount, bytes memory data) {
    address token0;
    address token1;
    address token0To;
    address token1To;
    uint256 positionAmount;
    (token0, token1, token0To, token1To, positionAmount, data) = abi.decode(
      param.data,
      (address, address, address, address, uint256, bytes)
    );

    Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    (long0Amount, long1Amount, data) = timeswapV2PeripheryCloseLendGivenPositionChoiceInternal(
      TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam({
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        token0Balance: param.long0Balance,
        token1Balance: param.long1Balance,
        tokenAmount: param.longAmount,
        data: data
      })
    );

    data = abi.encode(token0, token1, token0To, token1To, positionAmount, data);
  }

  function timeswapV2PoolLeverageCallback(
    TimeswapV2PoolLeverageCallbackParam calldata param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    address token0To;
    address token1To;
    uint256 positionAmount;
    (token0, token1, token0To, token1To, positionAmount, data) = abi.decode(
      param.data,
      (address, address, address, address, uint256, bytes)
    );

    address optionPair = Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    (, , uint256 shortAmountBurnt, ) = ITimeswapV2Option(optionPair).burn(
      TimeswapV2OptionBurnParam({
        strike: param.strike,
        maturity: param.maturity,
        token0To: token0To,
        token1To: token1To,
        transaction: TimeswapV2OptionBurn.GivenTokensAndLongs,
        amount0: param.long0Amount,
        amount1: param.long1Amount,
        data: bytes("")
      })
    );

    ITimeswapV2Option(optionPair).transferPosition(
      param.strike,
      param.maturity,
      msg.sender,
      TimeswapV2OptionPosition.Short,
      positionAmount - shortAmountBurnt
    );

    uint160 timeswapV2SqrtInterestRateAfter = ITimeswapV2Pool(msg.sender).sqrtInterestRate(
      param.strike,
      param.maturity
    );

    revert PassPoolLeverageCallbackInfo(timeswapV2SqrtInterestRateAfter, param.long0Amount, param.long1Amount, data);
  }

  function timeswapV2PeripheryCloseLendGivenPositionChoiceInternal(
    TimeswapV2PeripheryCloseLendGivenPositionChoiceInternalParam memory param
  ) internal virtual returns (uint256 long0Amount, uint256 long1Amount, bytes memory data);
}

