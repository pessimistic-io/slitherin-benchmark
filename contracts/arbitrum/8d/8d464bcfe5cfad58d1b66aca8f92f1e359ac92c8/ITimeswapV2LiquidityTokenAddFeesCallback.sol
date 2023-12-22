// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2LiquidityTokenAddFeesCallbackParam} from "./CallbackParam.sol";

interface ITimeswapV2LiquidityTokenAddFeesCallback {
  /// @dev Callback for `ITimeswapV2LiquidityToken.addFees`
  function timeswapV2LiquidityTokenAddFeesCallback(
    TimeswapV2LiquidityTokenAddFeesCallbackParam calldata param
  ) external returns (bytes memory data);
}

