// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";

import {StrikeConversion} from "./StrikeConversion.sol";

import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenPosition} from "./structs_Position.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";
import {UniswapV3PoolQuoterLibrary} from "./UniswapV3PoolQuoter.sol";

import {TimeswapV2PeripheryQuoterCloseBorrowGivenPosition} from "./TimeswapV2PeripheryQuoterCloseBorrowGivenPosition.sol";

import {TimeswapV2PeripheryCloseBorrowGivenPositionParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryCloseBorrowGivenPositionChoiceInternalParam, TimeswapV2PeripheryCloseBorrowGivenPositionInternalParam} from "./InternalParam.sol";

import {ITimeswapV2PeripheryUniswapV3QuoterCloseBorrowGivenPosition} from "./ITimeswapV2PeripheryUniswapV3QuoterCloseBorrowGivenPosition.sol";

import {Verify} from "./libraries_Verify.sol";

import {TimeswapV2PeripheryUniswapV3QuoterCloseBorrowGivenPositionParam} from "./QuoterParam.sol";
import {UniswapV3SwapParam, UniswapV3CalculateSwapParam} from "./SwapParam.sol";

import {OnlyOperatorReceiver} from "./OnlyOperatorReceiver.sol";
import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";
import {UniswapV3QuoterCallbackWithOptionalNative} from "./UniswapV3SwapQuoterCallback.sol";
import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryUniswapV3QuoterCloseBorrowGivenPosition is
  ITimeswapV2PeripheryUniswapV3QuoterCloseBorrowGivenPosition,
  TimeswapV2PeripheryQuoterCloseBorrowGivenPosition,
  OnlyOperatorReceiver,
  UniswapV3QuoterCallbackWithOptionalNative,
  Multicall
{
  using UniswapV3PoolLibrary for address;
  using UniswapV3PoolQuoterLibrary for address;

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenUniswapV3Factory
  )
    TimeswapV2PeripheryQuoterCloseBorrowGivenPosition(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  function closeBorrowGivenPosition(
    TimeswapV2PeripheryUniswapV3QuoterCloseBorrowGivenPositionParam calldata param,
    uint96 durationForward
  ) external returns (uint256 tokenAmount, uint160 timeswapV2SqrtInterestRateAfter, uint160 uniswapV3SqrtPriceAfter) {
    bytes memory data = abi.encode(msg.sender, param.uniswapV3Fee, param.to, param.isToken0);

    (, , data, timeswapV2SqrtInterestRateAfter) = closeBorrowGivenPosition(
      TimeswapV2PeripheryCloseBorrowGivenPositionParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        to: (param.isToken0 == param.isLong0) ? address(this) : param.to,
        isLong0: param.isLong0,
        positionAmount: param.positionAmount,
        data: data
      }),
      durationForward
    );

    (uniswapV3SqrtPriceAfter, tokenAmount) = abi.decode(data, (uint160, uint256));
  }

  function timeswapV2PeripheryCloseBorrowGivenPositionChoiceInternal(
    TimeswapV2PeripheryCloseBorrowGivenPositionChoiceInternalParam memory param
  ) internal override returns (uint256 token0Amount, uint256 token1Amount, bytes memory data) {
    (, uint24 uniswapV3Fee, , bool isToken0) = abi.decode(param.data, (address, uint24, address, bool));

    address pool = UniswapV3FactoryLibrary.getWithCheck(uniswapV3Factory, param.token0, param.token1, uniswapV3Fee);

    uint256 tokenAmountOut;

    data = abi.encode(param.token0, param.token1, uniswapV3Fee);
    data = abi.encode(false, data);

    (, tokenAmountOut) = pool.calculateSwap(
      UniswapV3CalculateSwapParam({
        zeroForOne: isToken0,
        exactInput: false,
        amount: StrikeConversion.turn(param.tokenAmount, param.strike, isToken0, true),
        strikeLimit: param.strike,
        data: data
      })
    );

    uint256 tokenAmountNotSwapped = StrikeConversion.dif(
      param.tokenAmount,
      tokenAmountOut,
      param.strike,
      !isToken0,
      true
    );

    token0Amount = isToken0 ? tokenAmountNotSwapped : tokenAmountOut;
    token1Amount = isToken0 ? tokenAmountOut : tokenAmountNotSwapped;

    data = param.data;
  }

  function timeswapV2PeripheryCloseBorrowGivenPositionInternal(
    TimeswapV2PeripheryCloseBorrowGivenPositionInternalParam memory param
  ) internal override returns (bytes memory data) {
    (address msgSender, uint24 uniswapV3Fee, address to, bool isToken0) = abi.decode(
      param.data,
      (address, uint24, address, bool)
    );

    uint256 tokenAmount = isToken0 ? param.token0Amount : param.token1Amount;
    if (isToken0 == param.isLong0) tokenAmount = param.positionAmount - tokenAmount;

    address pool = UniswapV3FactoryLibrary.get(uniswapV3Factory, param.token0, param.token1, uniswapV3Fee);

    uint256 uniswapV3SqrtPriceAfter;
    if ((isToken0 ? param.token1Amount : param.token0Amount) != 0) {
      data = abi.encode(
        isToken0 == param.isLong0 ? address(this) : msgSender,
        param.token0,
        param.token1,
        uniswapV3Fee
      );
      data = abi.encode(true, data);

      uint256 tokenAmountOut = isToken0 ? param.token1Amount : param.token0Amount;
      if (isToken0 != param.isLong0) tokenAmountOut = param.positionAmount - tokenAmountOut;

      uint256 tokenAmountIn;
      (tokenAmountIn, , uniswapV3SqrtPriceAfter) = pool.quoteSwap(
        UniswapV3SwapParam({
          recipient: isToken0 == param.isLong0 ? param.optionPair : to,
          zeroForOne: isToken0,
          exactInput: false,
          amount: tokenAmountOut,
          strikeLimit: param.strike,
          data: data
        })
      );

      tokenAmount += tokenAmountIn;
    } else (uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(pool).slot0();

    data = abi.encode(uniswapV3SqrtPriceAfter, tokenAmount);
  }
}

