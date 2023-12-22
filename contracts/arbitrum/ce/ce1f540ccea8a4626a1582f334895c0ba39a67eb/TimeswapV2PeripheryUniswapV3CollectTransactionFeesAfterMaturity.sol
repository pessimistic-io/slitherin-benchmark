// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Error} from "./Error.sol";

import {TimeswapV2LiquidityTokenPosition} from "./structs_Position.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";

import {TimeswapV2PeripheryCollectTransactionFeesAfterMaturity} from "./TimeswapV2PeripheryCollectTransactionFeesAfterMaturity.sol";

import {TimeswapV2PeripheryCollectTransactionFeesAfterMaturityParam} from "./contracts_structs_Param.sol";

import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";

import {ITimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturity} from "./ITimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturity.sol";

import {TimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturityParam} from "./structs_Param.sol";

import {NativeImmutableState, NativeWithdraws} from "./Native.sol";
import {UniswapImmutableState, UniswapV3Callback} from "./UniswapV3SwapCallback.sol";
import {SwapGetTotalToken} from "./SwapCalculator.sol";
import {Multicall} from "./Multicall.sol";
import {Math} from "./Math.sol";

contract TimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturity is
  ITimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturity,
  TimeswapV2PeripheryCollectTransactionFeesAfterMaturity,
  NativeImmutableState,
  NativeWithdraws,
  UniswapV3Callback,
  SwapGetTotalToken,
  Multicall
{
  using UniswapV3PoolLibrary for address;
  using Math for uint256;
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenLiquidityTokens,
    address chosenUniswapV3Factory,
    address chosenNative
  )
    TimeswapV2PeripheryCollectTransactionFeesAfterMaturity(
      chosenOptionFactory,
      chosenPoolFactory,
      chosenTokens,
      chosenLiquidityTokens
    )
    NativeImmutableState(chosenNative)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  /// @inheritdoc ITimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturity
  function collectTransactionFeesAfterMaturity(
    TimeswapV2PeripheryUniswapV3CollectTransactionFeesAfterMaturityParam calldata param
  ) external returns (uint256 tokenAmount) {
    if (param.deadline < block.timestamp) Error.deadlineReached(param.deadline);

    (, , uint256 shortFees) = ITimeswapV2LiquidityToken(liquidityTokens).feesEarnedOf(
      msg.sender,
      TimeswapV2LiquidityTokenPosition({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity
      })
    );

    ITimeswapV2LiquidityToken(liquidityTokens).transferFeesFrom(
      msg.sender,
      address(this),
      TimeswapV2LiquidityTokenPosition({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity
      }),
      0,
      0,
      param.shortRequested.min(shortFees)
    );

    (uint256 token0Amount, uint256 token1Amount) = collectTransactionFeesAfterMaturity(
      TimeswapV2PeripheryCollectTransactionFeesAfterMaturityParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        token0To: param.isToken0 ? param.to : address(this),
        token1To: param.isToken0 ? address(this) : param.to,
        shortRequested: param.shortRequested
      })
    );

    tokenAmount = swapGetTotalToken(
      param.token0,
      param.token1,
      param.strike,
      param.uniswapV3Fee,
      param.to,
      param.isToken0,
      token0Amount,
      token1Amount,
      true
    );

    if (tokenAmount < param.minTokenAmount) revert MinTokenReached(tokenAmount, param.minTokenAmount);

    emit CollectTransactionFeesAfterMaturity(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      param.uniswapV3Fee,
      msg.sender,
      param.to,
      param.isToken0,
      tokenAmount
    );
  }
}

