// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {StrikeConversion} from "./StrikeConversion.sol";
import {Error} from "./Error.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";
import {ITimeswapV2PoolFactory} from "./ITimeswapV2PoolFactory.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";

import {TimeswapV2PeripheryRebalance} from "./TimeswapV2PeripheryRebalance.sol";

import {TimeswapV2PeripheryRebalanceParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PeripheryRebalanceInternalParam} from "./InternalParam.sol";

import {ITimeswapV2PeripheryUniswapV3Rebalance} from "./ITimeswapV2PeripheryUniswapV3Rebalance.sol";

import {TimeswapV2PeripheryUniswapV3RebalanceParam} from "./structs_Param.sol";
import {UniswapV3SwapForRebalanceParam, UniswapV3CalculateSwapForRebalanceParam} from "./SwapParam.sol";

import {NativeImmutableState, NativeWithdraws} from "./Native.sol";
import {UniswapImmutableState, UniswapV3Callback} from "./UniswapV3SwapCallback.sol";
import {Multicall} from "./Multicall.sol";

/// @title Capable of rebalancing a Timeswap V2 pool
/// @author Timeswap Labs
contract TimeswapV2PeripheryUniswapV3Rebalance is
  ITimeswapV2PeripheryUniswapV3Rebalance,
  TimeswapV2PeripheryRebalance,
  NativeImmutableState,
  NativeWithdraws,
  UniswapV3Callback,
  Multicall
{
  using UniswapV3PoolLibrary for address;
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenUniswapV3Factory,
    address chosenNative
  )
    TimeswapV2PeripheryRebalance(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    NativeImmutableState(chosenNative)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  /// @inheritdoc ITimeswapV2PeripheryUniswapV3Rebalance
  function rebalance(
    TimeswapV2PeripheryUniswapV3RebalanceParam calldata param
  ) external override returns (uint256 tokenAmount, uint256 excessShortAmount) {
    if (param.deadline < block.timestamp) Error.deadlineReached(param.deadline);

    {
      uint256 transactionFee = ITimeswapV2PoolFactory(poolFactory).transactionFee();

      (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

      (uint256 token0Balance, uint256 token1Balance) = ITimeswapV2Pool(poolPair).totalLongBalanceAdjustFees(
        param.strike,
        param.maturity
      );

      address pool = UniswapV3FactoryLibrary.getWithCheck(
        uniswapV3Factory,
        param.token0,
        param.token1,
        param.uniswapV3Fee
      );

      bytes memory data = abi.encode(param.token0, param.token1, param.uniswapV3Fee);
      data = abi.encode(false, data);

      (bool zeroForOne, uint256 tokenAmountIn, uint256 tokenAmountOut) = pool.calculateSwapForRebalance(
        UniswapV3CalculateSwapForRebalanceParam({
          token0Amount: token0Balance,
          token1Amount: token1Balance,
          strikeLimit: param.strike,
          transactionFee: transactionFee,
          data: data
        })
      );

      if (tokenAmountOut == 0) revert NoRebalanceProfit();

      data = abi.encode(param.uniswapV3Fee, param.tokenTo, param.isToken0, transactionFee);

      bool givenLong0 = zeroForOne;
      tokenAmount = tokenAmountIn;
      if (param.isToken0 == zeroForOne) {
        uint256 maxAmountOut = StrikeConversion.convert(tokenAmountIn, param.strike, zeroForOne, true);
        if (tokenAmountOut < maxAmountOut) {
          givenLong0 = !zeroForOne;
          tokenAmount = tokenAmountOut;
        }
      }

      (, , excessShortAmount, data) = rebalance(
        TimeswapV2PeripheryRebalanceParam({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity,
          tokenTo: address(this),
          excessShortTo: param.excessShortTo,
          isLong0ToLong1: !zeroForOne,
          givenLong0: givenLong0,
          tokenAmount: tokenAmount,
          data: data
        })
      );

      tokenAmount = abi.decode(data, (uint256));
    }

    if (tokenAmount < param.minTokenAmount) revert MinTokenReached(tokenAmount, param.minTokenAmount);

    if (excessShortAmount < param.minExcessShortAmount)
      revert MinExcessShortReached(excessShortAmount, param.minExcessShortAmount);

    emit Rebalance(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      param.uniswapV3Fee,
      msg.sender,
      param.tokenTo,
      param.excessShortTo,
      param.isToken0,
      tokenAmount,
      excessShortAmount
    );
  }

  function timeswapV2PeripheryRebalanceInternal(
    TimeswapV2PeripheryRebalanceInternalParam memory param
  ) internal override returns (bytes memory data) {
    (uint24 uniswapV3Fee, address tokenTo, bool isToken0, uint256 transactionFee) = abi.decode(
      param.data,
      (uint24, address, bool, uint256)
    );

    address pool = UniswapV3FactoryLibrary.get(uniswapV3Factory, param.token0, param.token1, uniswapV3Fee);

    data = abi.encode(param.token0, param.token1, uniswapV3Fee);
    data = abi.encode(true, data);

    (uint256 tokenAmountIn, uint256 tokenAmountOut) = pool.swapForRebalance(
      UniswapV3SwapForRebalanceParam({
        recipient: isToken0 == param.isLong0ToLong1 ? address(this) : param.optionPair,
        zeroForOne: !param.isLong0ToLong1,
        exactInput: isToken0 == param.isLong0ToLong1,
        amount: isToken0 ? param.token1Amount : param.token0Amount,
        strikeLimit: param.strike,
        transactionFee: transactionFee,
        data: data
      })
    );

    if (isToken0 == param.isLong0ToLong1)
      IERC20(isToken0 ? param.token0 : param.token1).safeTransfer(
        param.optionPair,
        isToken0 ? param.token0Amount : param.token1Amount
      );

    uint256 tokenAmount = isToken0 == param.isLong0ToLong1
      ? tokenAmountOut - (isToken0 ? param.token0Amount : param.token1Amount)
      : (isToken0 ? param.token0Amount : param.token1Amount) - tokenAmountIn;

    IERC20(isToken0 ? param.token0 : param.token1).safeTransfer(tokenTo, tokenAmount);

    data = abi.encode(tokenAmount);
  }
}

