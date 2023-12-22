// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IV5AggregationExecutor} from "./IV5AggregationExecutor.sol";
import {IV5AggregationRouter} from "./IV5AggregationRouter.sol";
import {IV4AggregationExecutor} from "./IV4AggregationExecutor.sol";
import {IV4AggregationRouter} from "./IV4AggregationRouter.sol";

/// @notice An abstract class with the necessary class variables
/// to make a 1inch v5 aggregation router optimized.
abstract contract AggregationV5BaseRouter {
  /// @notice The contract used to execute the swap along an optimized path.
  IV5AggregationExecutor public immutable AGGREGATION_EXECUTOR;

  /// @notice The 1inch v5 aggregation router contract.
  IV5AggregationRouter public immutable AGGREGATION_ROUTER;

  /// @notice The input token being swapped.
  address public immutable TOKEN;

  /// @notice Where the tokens are transferred in the 1inch v5 aggregation router.
  /// It will match the AGGREGATION_EXECUTOR address.
  address public immutable SOURCE_RECEIVER;

  constructor(
    IV5AggregationExecutor aggregationExecutor,
    IV5AggregationRouter aggregationRouter,
    address token
  ) {
    AGGREGATION_EXECUTOR = aggregationExecutor;
    AGGREGATION_ROUTER = aggregationRouter;
    TOKEN = token;
    SOURCE_RECEIVER = address(aggregationExecutor);
  }
}

/// @notice An abstract class with the necessary class variables
/// to make a 1inch v4 aggregation router optimized.
abstract contract AggregationV4BaseRouter {
  /// @notice The contract used to execute the swap along an optimized path.
  IV4AggregationExecutor public immutable AGGREGATION_EXECUTOR;

  /// @notice The 1inch v4 aggregation router contract.
  IV4AggregationRouter public immutable AGGREGATION_ROUTER;

  /// @notice The input token being swapped.
  address public immutable TOKEN;

  /// @notice Where the tokens are transferred in the 1inch v4 aggregation router.
  /// It will match the AGGREGATION_EXECUTOR address.
  address public immutable SOURCE_RECEIVER;

  constructor(
    IV4AggregationExecutor aggregationExecutor,
    IV4AggregationRouter aggregationRouter,
    address token
  ) {
    AGGREGATION_EXECUTOR = aggregationExecutor;
    AGGREGATION_ROUTER = aggregationRouter;
    TOKEN = token;
    SOURCE_RECEIVER = address(aggregationExecutor);
  }
}

