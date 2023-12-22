// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.8;

import {StrikeConversion} from "./StrikeConversion.sol";
import {Math} from "./Math.sol";

import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3PoolLibrary} from "./UniswapV3Pool.sol";

import {UniswapV3SwapParam, UniswapV3CalculateSwapParam, UniswapV3CalculateForRemoveLiquidityParam, UniswapV3CalculateSwapGivenBalanceLimitParam} from "./SwapParam.sol";

abstract contract SwapCalculatorGivenBalanceLimit is UniswapImmutableState {
  using Math for uint256;
  using UniswapV3PoolLibrary for address;

  function calculateSwapGivenBalanceLimit(
    UniswapV3CalculateSwapGivenBalanceLimitParam memory param
  ) internal returns (bool removeStrikeLimit, uint256 token0Amount, uint256 token1Amount) {
    uint256 maxTokenAmountNotSwapped = StrikeConversion
      .turn(param.tokenAmount, param.strike, !param.isToken0, false)
      .min(param.isToken0 ? param.token0Balance : param.token1Balance);

    uint256 tokenAmountIn;
    uint256 tokenAmountNotSwapped;
    if ((param.isToken0 ? param.token1Balance : param.token0Balance) != 0) {
      address pool = UniswapV3FactoryLibrary.getWithCheck(
        uniswapV3Factory,
        param.token0,
        param.token1,
        param.uniswapV3Fee
      );

      {
        uint256 amount = StrikeConversion.turn(param.tokenAmount, param.strike, param.isToken0, false).min(
          param.isToken0 ? param.token1Balance : param.token0Balance
        );

        bytes memory data = abi.encode(param.token0, param.token1, param.uniswapV3Fee);
        data = abi.encode(false, data);

        (tokenAmountIn, ) = pool.calculateSwap(
          UniswapV3CalculateSwapParam({
            zeroForOne: !param.isToken0,
            exactInput: true,
            amount: amount,
            strikeLimit: param.strike,
            data: data
          })
        );
      }

      tokenAmountNotSwapped = StrikeConversion.dif(
        param.tokenAmount,
        tokenAmountIn,
        param.strike,
        !param.isToken0,
        false
      );

      if (tokenAmountNotSwapped > maxTokenAmountNotSwapped) {
        removeStrikeLimit = true;

        tokenAmountNotSwapped = maxTokenAmountNotSwapped;

        tokenAmountIn = StrikeConversion.dif(
          param.tokenAmount,
          tokenAmountNotSwapped,
          param.strike,
          param.isToken0,
          false
        );
      }
    } else tokenAmountNotSwapped = maxTokenAmountNotSwapped;

    token0Amount = param.isToken0 ? tokenAmountNotSwapped : tokenAmountIn;
    token1Amount = param.isToken0 ? tokenAmountIn : tokenAmountNotSwapped;
  }
}

abstract contract SwapCalculatorForRemoveLiquidity is UniswapImmutableState {
  using Math for uint256;
  using UniswapV3PoolLibrary for address;

  function calculateSwapForRemoveLiquidity(
    UniswapV3CalculateForRemoveLiquidityParam memory param
  )
    internal
    returns (
      bool removeStrikeLimit,
      uint256 token0AmountFromPool,
      uint256 token1AmountFromPool,
      uint256 token0AmountWithdraw,
      uint256 token1AmountWithdraw
    )
  {
    uint256 maxTokenAmountNotSwapped = StrikeConversion
      .turn(param.tokenAmountWithdraw, param.strike, !param.isToken0, false)
      .min(param.isToken0 ? param.token0Balance + param.token0Fees : param.token1Balance + param.token1Fees);

    uint256 tokenAmountIn;
    uint256 tokenAmountNotSwapped;
    if ((param.isToken0 ? param.token1Balance : param.token0Balance) != 0) {
      address pool = UniswapV3FactoryLibrary.getWithCheck(
        uniswapV3Factory,
        param.token0,
        param.token1,
        param.uniswapV3Fee
      );

      {
        uint256 amount = StrikeConversion.turn(param.tokenAmountWithdraw, param.strike, param.isToken0, false).min(
          param.isToken0 ? param.token1Balance + param.token0Fees : param.token0Balance + param.token1Fees
        );

        bytes memory data = abi.encode(param.token0, param.token1, param.uniswapV3Fee);
        data = abi.encode(false, data);

        (tokenAmountIn, ) = pool.calculateSwap(
          UniswapV3CalculateSwapParam({
            zeroForOne: !param.isToken0,
            exactInput: true,
            amount: amount,
            strikeLimit: param.strike,
            data: data
          })
        );
      }

      {
        uint256 converted = StrikeConversion.combine(
          param.isToken0 ? 0 : tokenAmountIn - (param.isToken0 ? param.token1Fees : param.token0Fees),
          param.isToken0 ? tokenAmountIn - (param.isToken0 ? param.token1Fees : param.token0Fees) : 0,
          param.strike,
          true
        );

        if (converted > param.tokenAmountFromPool)
          tokenAmountIn =
            StrikeConversion.turn(param.tokenAmountFromPool, param.strike, param.isToken0, false) +
            (param.isToken0 ? param.token1Fees : param.token0Fees);
      }

      tokenAmountNotSwapped = StrikeConversion.dif(
        param.tokenAmountWithdraw,
        tokenAmountIn,
        param.strike,
        !param.isToken0,
        false
      );

      if (tokenAmountNotSwapped > maxTokenAmountNotSwapped) {
        removeStrikeLimit = true;

        tokenAmountNotSwapped = maxTokenAmountNotSwapped;

        tokenAmountIn = StrikeConversion.dif(
          param.tokenAmountWithdraw,
          tokenAmountNotSwapped,
          param.strike,
          param.isToken0,
          false
        );
      }
    } else tokenAmountNotSwapped = maxTokenAmountNotSwapped;

    token0AmountWithdraw = param.isToken0 ? tokenAmountNotSwapped : tokenAmountIn;
    token1AmountWithdraw = param.isToken0 ? tokenAmountIn : tokenAmountNotSwapped;

    uint256 tokenAmountFromPoolNotPreferred = tokenAmountIn > (param.isToken0 ? param.token1Fees : param.token0Fees)
      ? tokenAmountIn.unsafeSub(param.isToken0 ? param.token1Fees : param.token0Fees)
      : 0;

    uint256 tokenAmountFronPoolPreferred = StrikeConversion.dif(
      param.tokenAmountFromPool,
      tokenAmountFromPoolNotPreferred,
      param.strike,
      param.isToken0,
      false
    );

    if (tokenAmountFronPoolPreferred > (param.isToken0 ? param.token0Balance : param.token1Balance)) {
      tokenAmountFronPoolPreferred = param.isToken0 ? param.token0Balance : param.token1Balance;

      tokenAmountFromPoolNotPreferred = StrikeConversion.dif(
        param.tokenAmountFromPool,
        tokenAmountFronPoolPreferred,
        param.strike,
        !param.isToken0,
        false
      );
    }

    token0AmountFromPool = param.isToken0 ? tokenAmountFronPoolPreferred : tokenAmountFromPoolNotPreferred;
    token1AmountFromPool = param.isToken0 ? tokenAmountFromPoolNotPreferred : tokenAmountFronPoolPreferred;
  }
}

abstract contract SwapGetTotalToken is UniswapImmutableState {
  using UniswapV3PoolLibrary for address;

  function swapGetTotalToken(
    address token0,
    address token1,
    uint256 strike,
    uint24 uniswapV3Fee,
    address to,
    bool isToken0,
    uint256 token0Amount,
    uint256 token1Amount,
    bool removeStrikeLimit
  ) internal returns (uint256 tokenAmount) {
    tokenAmount = isToken0 ? token0Amount : token1Amount;

    if ((isToken0 ? token1Amount : token0Amount) != 0) {
      address pool = UniswapV3FactoryLibrary.getWithCheck(uniswapV3Factory, token0, token1, uniswapV3Fee);

      bytes memory data = abi.encode(token0, token1, uniswapV3Fee);
      data = abi.encode(true, data);

      (, uint256 tokenAmountOut) = pool.swap(
        UniswapV3SwapParam({
          recipient: to,
          zeroForOne: !isToken0,
          exactInput: true,
          amount: isToken0 ? token1Amount : token0Amount,
          strikeLimit: removeStrikeLimit ? 0 : strike,
          data: data
        })
      );

      tokenAmount += tokenAmountOut;
    }
  }
}

