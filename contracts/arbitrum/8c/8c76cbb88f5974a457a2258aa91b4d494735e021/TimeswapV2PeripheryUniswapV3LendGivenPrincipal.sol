// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {Error} from "./Error.sol";
import {Math} from "./Math.sol";

import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";

import {TimeswapV2PeripheryLendGivenPrincipal} from "./TimeswapV2PeripheryLendGivenPrincipal.sol";

import {TimeswapV2PeripheryLendGivenPrincipalParam} from "./contracts_structs_Param.sol";
import {TimeswapV2PeripheryLendGivenPrincipalInternalParam} from "./InternalParam.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";

import {ITimeswapV2PeripheryUniswapV3LendGivenPrincipal} from "./ITimeswapV2PeripheryUniswapV3LendGivenPrincipal.sol";

import {TimeswapV2PeripheryUniswapV3LendGivenPrincipalParam} from "./structs_Param.sol";
import {UniswapV3SwapParam} from "./SwapParam.sol";

import {NativeImmutableState} from "./Native.sol";
import {UniswapImmutableState, UniswapV3CallbackWithNative} from "./UniswapV3SwapCallback.sol";
import {Multicall} from "./Multicall.sol";

/// @title Capable of lending in the Timeswap V2 Protocol given a principal amount
/// @author Timeswap Labs
contract TimeswapV2PeripheryUniswapV3LendGivenPrincipal is
  ITimeswapV2PeripheryUniswapV3LendGivenPrincipal,
  TimeswapV2PeripheryLendGivenPrincipal,
  NativeImmutableState,
  UniswapV3CallbackWithNative,
  Multicall
{
  using UniswapV3PoolLibrary for address;
  using Math for uint256;
  using SafeERC20 for IERC20;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenUniswapV3Factory,
    address chosenNative
  )
    TimeswapV2PeripheryLendGivenPrincipal(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    NativeImmutableState(chosenNative)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  /// @inheritdoc ITimeswapV2PeripheryUniswapV3LendGivenPrincipal
  function lendGivenPrincipal(
    TimeswapV2PeripheryUniswapV3LendGivenPrincipalParam calldata param
  ) external payable override returns (uint256 positionAmount) {
    if (param.deadline < block.timestamp) Error.deadlineReached(param.deadline);

    address pool = UniswapV3FactoryLibrary.getWithCheck(
      uniswapV3Factory,
      param.token0,
      param.token1,
      param.uniswapV3Fee
    );

    bytes memory data = abi.encode(msg.sender, param.token0, param.token1, param.uniswapV3Fee);
    data = abi.encode(true, data);

    (uint256 tokenAmountIn, uint256 tokenAmountOut) = pool.swap(
      UniswapV3SwapParam({
        recipient: address(this),
        zeroForOne: param.isToken0,
        exactInput: true,
        amount: param.tokenAmount,
        strikeLimit: param.strike,
        data: data
      })
    );

    data = abi.encode(msg.sender, param.isToken0);

    (positionAmount, ) = lendGivenPrincipal(
      TimeswapV2PeripheryLendGivenPrincipalParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        to: param.to,
        token0Amount: param.isToken0 ? param.tokenAmount.unsafeSub(tokenAmountIn) : tokenAmountOut,
        token1Amount: param.isToken0 ? tokenAmountOut : param.tokenAmount.unsafeSub(tokenAmountIn),
        data: data
      })
    );

    if (positionAmount < param.minReturnAmount) revert MinPositionReached(positionAmount, param.minReturnAmount);

    emit LendGivenPrincipal(
      param.token0,
      param.token1,
      param.strike,
      param.maturity,
      param.uniswapV3Fee,
      msg.sender,
      param.to,
      param.isToken0,
      param.tokenAmount,
      positionAmount
    );
  }

  function timeswapV2PeripheryLendGivenPrincipalInternal(
    TimeswapV2PeripheryLendGivenPrincipalInternalParam memory param
  ) internal override returns (bytes memory data) {
    (address msgSender, bool isToken0) = abi.decode(param.data, (address, bool));

    if ((isToken0 ? param.token0Amount : param.token1Amount) != 0)
      pay(
        isToken0 ? param.token0 : param.token1,
        msgSender,
        param.optionPair,
        isToken0 ? param.token0Amount : param.token1Amount
      );

    if ((isToken0 ? param.token1Amount : param.token0Amount) != 0)
      IERC20(isToken0 ? param.token1 : param.token0).safeTransfer(
        param.optionPair,
        isToken0 ? param.token1Amount : param.token0Amount
      );

    data = bytes("");
  }
}

