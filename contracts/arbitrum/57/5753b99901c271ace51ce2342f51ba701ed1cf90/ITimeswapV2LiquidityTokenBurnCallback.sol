// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2LiquidityTokenBurnCallbackParam} from "./CallbackParam.sol";

interface ITimeswapV2LiquidityTokenBurnCallback {
  /// @dev Callback for `ITimeswapV2LiquidityToken.burn`
  function timeswapV2LiquidityTokenBurnCallback(
    TimeswapV2LiquidityTokenBurnCallbackParam calldata param
  ) external returns (bytes memory data);
}

