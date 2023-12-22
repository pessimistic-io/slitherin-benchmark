// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";
import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";

import {UniswapImmutableState, UniswapCalculate} from "./UniswapV3SwapCallback.sol";

import {Verify} from "./libraries_Verify.sol";
import {UniswapV3PoolQuoterLibrary} from "./UniswapV3PoolQuoter.sol";

abstract contract UniswapV3QuoterCallback is UniswapCalculate, IUniswapV3SwapCallback {
  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external view override {
    (bool hasQuote, bytes memory innerData) = abi.decode(data, (bool, bytes));

    if (hasQuote) {
      (address token0, address token1, uint24 uniswapV3Fee) = abi.decode(innerData, (address, address, uint24));

      Verify.uniswapV3Pool(uniswapV3Factory, token0, token1, uniswapV3Fee);

      (uint160 uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(msg.sender).slot0();

      UniswapV3PoolQuoterLibrary.passUniswapV3SwapCallbackInfo(amount0Delta, amount1Delta, uniswapV3SqrtPriceAfter);
    } else uniswapCalculate(amount0Delta, amount1Delta, innerData);
  }
}

abstract contract UniswapV3QuoterCallbackWithNative is UniswapCalculate, IUniswapV3SwapCallback {
  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external view override {
    (bool hasQuote, bytes memory innerData) = abi.decode(data, (bool, bytes));

    if (hasQuote) {
      (, address token0, address token1, uint24 uniswapV3Fee) = abi.decode(
        innerData,
        (address, address, address, uint24)
      );

      Verify.uniswapV3Pool(uniswapV3Factory, token0, token1, uniswapV3Fee);

      (uint160 uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(msg.sender).slot0();

      UniswapV3PoolQuoterLibrary.passUniswapV3SwapCallbackInfo(amount0Delta, amount1Delta, uniswapV3SqrtPriceAfter);
    } else uniswapCalculate(amount0Delta, amount1Delta, innerData);
  }
}

abstract contract UniswapV3QuoterCallbackWithOptionalNative is UniswapCalculate, IUniswapV3SwapCallback {
  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external view override {
    (bool hasQuote, bytes memory innerData) = abi.decode(data, (bool, bytes));

    if (hasQuote) {
      (, address token0, address token1, uint24 uniswapV3Fee) = abi.decode(
        innerData,
        (address, address, address, uint24)
      );

      Verify.uniswapV3Pool(uniswapV3Factory, token0, token1, uniswapV3Fee);

      (uint160 uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(msg.sender).slot0();

      UniswapV3PoolQuoterLibrary.passUniswapV3SwapCallbackInfo(amount0Delta, amount1Delta, uniswapV3SqrtPriceAfter);
    } else uniswapCalculate(amount0Delta, amount1Delta, innerData);
  }
}

