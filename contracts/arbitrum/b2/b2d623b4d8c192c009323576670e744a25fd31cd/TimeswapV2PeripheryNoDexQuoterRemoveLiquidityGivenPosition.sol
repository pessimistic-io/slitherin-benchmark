// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Math} from "./Math.sol";
import {StrikeConversion} from "./StrikeConversion.sol";

import {TimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition} from "./TimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition.sol";

import {TimeswapV2PeripheryRemoveLiquidityGivenPositionParam, FeesAndReturnedDelta, ExcessDelta} from "./structs_Param.sol";
import {TimeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternalParam, TimeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternalParam, TimeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternalParam} from "./InternalParam.sol";

import {ITimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPosition} from "./ITimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPosition.sol";

import {TimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPositionParam} from "./QuoterParam.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPosition is
  ITimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPosition,
  TimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition,
  OnlyOperatorReceiver,
  Multicall
{
  using Math for uint256;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenLiquidityTokens
  )
    TimeswapV2PeripheryQuoterRemoveLiquidityGivenPosition(
      chosenOptionFactory,
      chosenPoolFactory,
      chosenTokens,
      chosenLiquidityTokens
    )
  {}

  function removeLiquidityGivenPosition(
    TimeswapV2PeripheryNoDexQuoterRemoveLiquidityGivenPositionParam calldata param,
    uint96 durationForward
  )
    external
    returns (
      uint256 token0Amount,
      uint256 token1Amount,
      FeesAndReturnedDelta memory feesAndReturnedDelta,
      ExcessDelta memory excessDelta,
      uint160 timeswapV2LiquidityAfter
    )
  {
    bytes memory data = abi.encode(msg.sender, param.isToken0);

    (
      token0Amount,
      token1Amount,
      feesAndReturnedDelta,
      excessDelta,
      ,
      timeswapV2LiquidityAfter
    ) = removeLiquidityGivenPosition(
      TimeswapV2PeripheryRemoveLiquidityGivenPositionParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.isToken0 ? param.tokenTo : address(this),
        token1To: param.isToken0 ? address(this) : param.tokenTo,
        liquidityAmount: param.liquidityAmount,
        excessLong0Amount: param.excessLong0Amount,
        excessLong1Amount: param.excessLong1Amount,
        excessShortAmount: param.excessShortAmount,
        data: data
      }),
      durationForward
    );
  }

  function timeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternal(
    TimeswapV2PeripheryRemoveLiquidityGivenPositionChoiceInternalParam memory param
  )
    internal
    pure
    override
    returns (
      uint256 token0AmountFromPool,
      uint256 token1AmountFromPool,
      uint256 token0AmountWithdraw,
      uint256 token1AmountWithdraw,
      bytes memory data
    )
  {
    (address msgSender, bool isToken0) = abi.decode(param.data, (address, bool));

    {
      uint256 token0Balance = param.token0Balance.min(
        StrikeConversion.turn(param.tokenAmountFromPool, param.strike, false, false)
      ) + param.excessToken0Amount;
      uint256 token1Balance = param.token1Balance.min(
        StrikeConversion.turn(param.tokenAmountFromPool, param.strike, true, false)
      ) + param.excessToken1Amount;

      uint256 tokenAmountWithdrawPreferred = StrikeConversion
        .turn(param.tokenAmountWithdraw, param.strike, !isToken0, false)
        .min(isToken0 ? token0Balance : token1Balance);

      uint256 tokenAmountWithdrawNotPreferred = StrikeConversion.dif(
        param.tokenAmountWithdraw,
        tokenAmountWithdrawPreferred,
        param.strike,
        isToken0,
        false
      );
      tokenAmountWithdrawNotPreferred = tokenAmountWithdrawNotPreferred.min(isToken0 ? token1Balance : token0Balance);

      token0AmountWithdraw = isToken0 ? tokenAmountWithdrawPreferred : tokenAmountWithdrawNotPreferred;
      token1AmountWithdraw = isToken0 ? tokenAmountWithdrawNotPreferred : tokenAmountWithdrawPreferred;
    }

    {
      uint256 tokenAmountFromPoolPreferred = StrikeConversion
        .turn(param.tokenAmountFromPool, param.strike, !isToken0, false)
        .min(isToken0 ? param.token0Balance : param.token1Balance);

      uint256 tokenAmountFromPoolNotPreferred = StrikeConversion.dif(
        param.tokenAmountFromPool,
        tokenAmountFromPoolPreferred,
        param.strike,
        isToken0,
        false
      );

      token0AmountFromPool = isToken0 ? tokenAmountFromPoolPreferred : tokenAmountFromPoolNotPreferred;
      token1AmountFromPool = isToken0 ? tokenAmountFromPoolNotPreferred : tokenAmountFromPoolPreferred;
    }

    data = abi.encode(msgSender);
  }

  function timeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternal(
    TimeswapV2PeripheryRemoveLiquidityGivenPositionNoBurnChoiceInternalParam memory param
  ) internal pure override returns (uint256 token0AmountWithdraw, uint256 token1AmountWithdraw, bytes memory data) {
    (address msgSender, bool isToken0) = abi.decode(param.data, (address, bool));

    uint256 longAmount = StrikeConversion.combine(
      param.excessToken0Amount,
      param.excessToken1Amount,
      param.strike,
      true
    );

    if (longAmount == param.tokenAmountWithdraw) {
      token0AmountWithdraw = param.excessToken0Amount;
      token1AmountWithdraw = param.excessToken1Amount;
    } else {
      uint256 tokenAmountWithdrawPreferred = StrikeConversion
        .turn(param.tokenAmountWithdraw, param.strike, !isToken0, false)
        .min(isToken0 ? param.excessToken0Amount : param.excessToken1Amount);

      uint256 tokenAmountWithdrawNotPreferred = StrikeConversion.dif(
        param.tokenAmountWithdraw,
        tokenAmountWithdrawPreferred,
        param.strike,
        isToken0,
        false
      );

      token0AmountWithdraw = isToken0 ? tokenAmountWithdrawPreferred : tokenAmountWithdrawNotPreferred;
      token1AmountWithdraw = isToken0 ? tokenAmountWithdrawNotPreferred : tokenAmountWithdrawPreferred;
    }

    data = abi.encode(msgSender);
  }

  function timeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternal(
    TimeswapV2PeripheryRemoveLiquidityGivenPositionTransferInternalParam memory
  ) internal pure override returns (bytes memory data) {
    data = "";
  }
}

