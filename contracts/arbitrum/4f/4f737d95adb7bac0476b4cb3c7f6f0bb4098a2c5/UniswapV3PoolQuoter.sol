// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3PoolActions} from "./IUniswapV3PoolActions.sol";
import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";
import {SafeCast} from "./libraries_SafeCast.sol";

import {FullMath} from "./FullMath.sol";
import {Math} from "./Math.sol";
import {CatchError} from "./CatchError.sol";

import {PriceConversion} from "./PriceConversion.sol";

import {UniswapV3SwapParam, UniswapV3SwapForRebalanceParam} from "./SwapParam.sol";

library UniswapV3PoolQuoterLibrary {
  using SafeCast for uint256;
  using PriceConversion for uint256;
  using Math for uint256;
  using CatchError for bytes;

  error PassUniswapV3SwapCallbackInfo(int256 amount0, int256 amount1, uint160 uniswapV3SqrtPriceAfter);

  function passUniswapV3SwapCallbackInfo(
    int256 amount0,
    int256 amount1,
    uint160 uniswapV3SqrtPriceAfter
  ) internal pure {
    revert PassUniswapV3SwapCallbackInfo(amount0, amount1, uniswapV3SqrtPriceAfter);
  }

  /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
  uint160 internal constant MIN_SQRT_RATIO = 4295128739;
  /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
  uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

  function quoteSwap(
    address pool,
    UniswapV3SwapParam memory param
  ) internal returns (uint256 tokenAmountIn, uint256 tokenAmountOut, uint160 uniswapV3SqrtPriceAfter) {
    (uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(pool).slot0();

    uint160 sqrtStrike = param.strikeLimit != 0
      ? param.strikeLimit.convertTsToUni()
      : (param.zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1);

    if (sqrtStrike <= MIN_SQRT_RATIO) sqrtStrike = MIN_SQRT_RATIO + 1;
    if (sqrtStrike >= MAX_SQRT_RATIO) sqrtStrike = MAX_SQRT_RATIO - 1;

    if (param.zeroForOne ? (uniswapV3SqrtPriceAfter > sqrtStrike) : (uniswapV3SqrtPriceAfter < sqrtStrike)) {
      int256 amount0;
      int256 amount1;

      try
        IUniswapV3PoolActions(pool).swap(
          address(this),
          param.zeroForOne,
          param.exactInput ? param.amount.toInt256() : -param.amount.toInt256(),
          sqrtStrike,
          param.data
        )
      {} catch (bytes memory reason) {
        (amount0, amount1, uniswapV3SqrtPriceAfter) = handleRevert(reason);
      }

      (tokenAmountIn, tokenAmountOut) = param.zeroForOne
        ? (uint256(amount0), uint256(-amount1))
        : (uint256(amount1), uint256(-amount0));
    } else (uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(pool).slot0();
  }

  function quoteSwapForRebalance(
    address pool,
    UniswapV3SwapForRebalanceParam memory param
  ) internal returns (uint256 tokenAmountIn, uint256 tokenAmountOut, uint160 uniswapV3SqrtPriceAfter) {
    uint160 sqrtStrike = (
      param.zeroForOne
        ? FullMath.mulDiv(
          param.strikeLimit.convertTsToUni(),
          1 << 16,
          (uint256(1) << 16).unsafeSub(param.transactionFee),
          true
        )
        : FullMath.mulDiv(
          param.strikeLimit.convertTsToUni(),
          (uint256(1) << 16).unsafeSub(param.transactionFee),
          1 << 16,
          false
        )
    ).toUint160();

    int amount0;
    int amount1;

    if (sqrtStrike <= MIN_SQRT_RATIO) sqrtStrike = MIN_SQRT_RATIO + 1;
    if (sqrtStrike >= MAX_SQRT_RATIO) sqrtStrike = MAX_SQRT_RATIO - 1;

    try
      IUniswapV3PoolActions(pool).swap(
        address(this),
        param.zeroForOne,
        param.exactInput ? param.amount.toInt256() : -param.amount.toInt256(),
        sqrtStrike,
        param.data
      )
    {} catch (bytes memory reason) {
      (amount0, amount1, uniswapV3SqrtPriceAfter) = handleRevert(reason);
    }

    (tokenAmountIn, tokenAmountOut) = param.zeroForOne
      ? (uint256(amount0), uint256(-amount1))
      : (uint256(amount1), uint256(-amount0));
  }

  function handleRevert(
    bytes memory reason
  ) private pure returns (int256 amount0, int256 amount1, uint160 uniswapV3SqrtPriceAfter) {
    return abi.decode(reason.catchError(PassUniswapV3SwapCallbackInfo.selector), (int256, int256, uint160));
  }
}

