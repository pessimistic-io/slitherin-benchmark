// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {TimeswapV2PoolAddFeesCallbackParam} from "./CallbackParam.sol";

/// @dev The interface that needs to be implemented by a contract calling the addFees function.
interface ITimeswapV2PoolAddFeesCallback {
  /// @dev Require the transfer of long0 position, long1 position, and short position into the pool.
  /// @param data The bytes of data to be sent to msg.sender.
  function timeswapV2PoolAddFeesCallback(
    TimeswapV2PoolAddFeesCallbackParam calldata param
  ) external returns (bytes memory data);
}

