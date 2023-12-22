// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";
import {UniswapV3PoolQuoterLibrary} from "./UniswapV3PoolQuoter.sol";
import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";

import {TimeswapV2PeripheryQuoterBorrowGivenPrincipal} from "./TimeswapV2PeripheryQuoterBorrowGivenPrincipal.sol";

import {TimeswapV2PeripheryBorrowGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryBorrowGivenPrincipalInternalParam} from "./InternalParam.sol";

import {ITimeswapV2PeripheryUniswapV3QuoterBorrowGivenPrincipal} from "./ITimeswapV2PeripheryUniswapV3QuoterBorrowGivenPrincipal.sol";

import {TimeswapV2PeripheryUniswapV3QuoterBorrowGivenPrincipalParam} from "./QuoterParam.sol";
import {UniswapV3CalculateSwapParam} from "./SwapParam.sol";
import {UniswapV3SwapParam} from "./SwapParam.sol";

import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";
import {UniswapV3QuoterCallbackWithOptionalNative} from "./UniswapV3SwapQuoterCallback.sol";
import {Multicall} from "./Multicall.sol";

contract TimeswapV2PeripheryUniswapV3QuoterBorrowGivenPrincipal is
  ITimeswapV2PeripheryUniswapV3QuoterBorrowGivenPrincipal,
  TimeswapV2PeripheryQuoterBorrowGivenPrincipal,
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
    TimeswapV2PeripheryQuoterBorrowGivenPrincipal(chosenOptionFactory, chosenPoolFactory, chosenTokens)
    UniswapImmutableState(chosenUniswapV3Factory)
  {}

  struct Cache {
    bool exactInput;
    bool removeStrikeLimit;
    uint256 tokenAmountIn;
    uint256 tokenAmountOut;
  }

  function borrowGivenPrincipal(
    TimeswapV2PeripheryUniswapV3QuoterBorrowGivenPrincipalParam calldata param,
    uint96 durationForward
  )
    external
    returns (uint256 positionAmount, uint160 timeswapV2SqrtInterestRateAfter, uint160 uniswapV3SqrtPriceAfter)
  {
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

    Cache memory cache;
    bytes memory data = abi.encode(param.token0, param.token1, param.uniswapV3Fee);
    data = abi.encode(false, data);
    if ((param.isToken0 ? token1Balance : token0Balance) != 0) {
      (cache.tokenAmountIn, cache.tokenAmountOut) = pool.calculateSwap(
        UniswapV3CalculateSwapParam({
          zeroForOne: !param.isToken0,
          exactInput: false,
          amount: param.tokenAmount,
          strikeLimit: param.strike,
          data: data
        })
      );

      if (cache.tokenAmountIn > (param.isToken0 ? token1Balance : token0Balance))
        (cache.tokenAmountIn, cache.tokenAmountOut) = pool.calculateSwap(
          UniswapV3CalculateSwapParam({
            zeroForOne: !param.isToken0,
            exactInput: (cache.exactInput = true),
            amount: param.isToken0 ? token1Balance : token0Balance,
            strikeLimit: param.strike,
            data: data
          })
        );
    }

    if (param.tokenAmount - cache.tokenAmountOut > (param.isToken0 ? token0Balance : token1Balance)) {
      cache.removeStrikeLimit = true;

      UniswapV3CalculateSwapParam memory internalParam = UniswapV3CalculateSwapParam({
        zeroForOne: !param.isToken0,
        exactInput: (cache.exactInput = false),
        amount: param.tokenAmount - (param.isToken0 ? token0Balance : token1Balance),
        strikeLimit: 0,
        data: data
      });

      (cache.tokenAmountIn, cache.tokenAmountOut) = pool.calculateSwap(internalParam);
    }

    data = abi.encode(
      msg.sender,
      param.uniswapV3Fee,
      param.tokenTo,
      param.isToken0,
      cache.exactInput,
      cache.removeStrikeLimit,
      cache.tokenAmountOut
    );

    (positionAmount, data, timeswapV2SqrtInterestRateAfter) = borrowGivenPrincipal(
      TimeswapV2PeripheryBorrowGivenPrincipalParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        tokenTo: param.isToken0 == param.isLong0 ? address(this) : param.tokenTo,
        longTo: param.longTo,
        isLong0: param.isLong0,
        token0Amount: param.isToken0 ? param.tokenAmount - cache.tokenAmountOut : cache.tokenAmountIn,
        token1Amount: param.isToken0 ? cache.tokenAmountIn : param.tokenAmount - cache.tokenAmountOut,
        data: data
      }),
      durationForward
    );

    uniswapV3SqrtPriceAfter = abi.decode(data, (uint160));
  }

  function timeswapV2PeripheryBorrowGivenPrincipalInternal(
    TimeswapV2PeripheryBorrowGivenPrincipalInternalParam memory param
  ) internal override returns (bytes memory data) {
    (
      address msgSender,
      uint24 uniswapV3Fee,
      address tokenTo,
      bool isToken0,
      bool exactInput,
      bool removeStrikeLimit,
      uint256 tokenAmountOut
    ) = abi.decode(param.data, (address, uint24, address, bool, bool, bool, uint256));
    uint160 uniswapV3SqrtPriceAfter;
    address pool = UniswapV3FactoryLibrary.get(uniswapV3Factory, param.token0, param.token1, uniswapV3Fee);

    if ((exactInput ? (isToken0 ? param.token1Amount : param.token0Amount) : tokenAmountOut) != 0) {
      data = abi.encode(
        isToken0 == param.isLong0 ? address(this) : msgSender,
        param.token0,
        param.token1,
        uniswapV3Fee
      );
      data = abi.encode(true, data);

      (, tokenAmountOut, uniswapV3SqrtPriceAfter) = pool.quoteSwap(
        UniswapV3SwapParam({
          recipient: isToken0 == param.isLong0 ? address(this) : tokenTo,
          zeroForOne: !isToken0,
          exactInput: exactInput,
          amount: exactInput ? (isToken0 ? param.token1Amount : param.token0Amount) : tokenAmountOut,
          strikeLimit: removeStrikeLimit ? 0 : param.strike,
          data: data
        })
      );
    } else (uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(pool).slot0();

    data = abi.encode(uniswapV3SqrtPriceAfter);
  }
}

