// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2LiquidityTokenMintCallbackParam} from "./CallbackParam.sol";

interface ITimeswapV2LiquidityTokenMintCallback {
  /// @dev Callback for `ITimeswapV2LiquidityToken.mint`
  function timeswapV2LiquidityTokenMintCallback(
    TimeswapV2LiquidityTokenMintCallbackParam calldata param
  ) external returns (bytes memory data);
}

