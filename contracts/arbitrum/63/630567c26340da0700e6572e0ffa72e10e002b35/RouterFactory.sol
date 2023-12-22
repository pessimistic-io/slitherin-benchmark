// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IV5AggregationExecutor} from "./IV5AggregationExecutor.sol";
import {IV5AggregationRouter} from "./IV5AggregationRouter.sol";
import {IV4AggregationExecutor} from "./IV4AggregationExecutor.sol";
import {IV4AggregationRouter} from "./IV4AggregationRouter.sol";
import {Create2} from "./Create2.sol";
import {V5Router} from "./V5Router.sol";
import {V4Router} from "./V4Router.sol";

/// @notice A factory for deploying an optimized router for a given asset and router type.
contract RouterFactory {
  error RouterTypeDoesNotExist();

  enum RouterType {
    V4AggregationRouter,
    V5AggregationRouter
  }

  /// @notice The 1inch v5 contract used to execute the swap along an optimized token swapping path.
  IV5AggregationExecutor public immutable V5_AGGREGATION_EXECUTOR;

  /// @notice The 1inch v5 aggregation router contract.
  IV5AggregationRouter public immutable V5_AGGREGATION_ROUTER;

  /// @notice The 1inch v4 aggregation router contract used to execute the swap along an optimized
  /// token swapping path.
  IV4AggregationExecutor public immutable V4_AGGREGATION_EXECUTOR;

  /// @notice The 1inch v4 aggregation router contract.
  IV4AggregationRouter public immutable V4_AGGREGATION_ROUTER;

  event RouterDeployed(RouterType type_, address indexed asset);

  constructor(
    IV5AggregationExecutor v5AggregationExecutor,
    IV5AggregationRouter v5AggregationRouter,
    IV4AggregationExecutor v4AggregationExecutor,
    IV4AggregationRouter v4AggregationRouter
  ) {
    V5_AGGREGATION_EXECUTOR = v5AggregationExecutor;
    V5_AGGREGATION_ROUTER = v5AggregationRouter;
    V4_AGGREGATION_EXECUTOR = v4AggregationExecutor;
    V4_AGGREGATION_ROUTER = v4AggregationRouter;
  }

  function deploy(RouterType type_, address asset) external returns (address) {
    bytes32 salt = _salt(asset);
    address router;
    if (type_ == RouterType.V5AggregationRouter) {
      router = address(
        new V5Router{salt: salt}(
                    V5_AGGREGATION_ROUTER,
                    V5_AGGREGATION_EXECUTOR,
                    asset
                )
      );
    } else if (type_ == RouterType.V4AggregationRouter) {
      router = address(
        new V4Router{salt: salt}(
                    V4_AGGREGATION_ROUTER,
                    V4_AGGREGATION_EXECUTOR,
                    asset
                )
      );
    } else {
      revert RouterTypeDoesNotExist();
    }
    emit RouterDeployed(type_, asset);
    return router;
  }

  function computeAddress(RouterType type_, address asset) external view returns (address) {
    if (type_ == RouterType.V4AggregationRouter) {
      return _computeV4AggregationRouterAddress(asset);
    } else if (type_ == RouterType.V5AggregationRouter) {
      return _computeV5AggregationRouterAddress(asset);
    } else {
      // In practice this branch will never be hit, and is
      // meant to catch situations in development when a
      // new RouterType has been added and it is not yet
      // supported in this function.
      revert RouterTypeDoesNotExist();
    }
  }

  function _computeV4AggregationRouterAddress(address asset) internal view returns (address) {
    return Create2.computeCreate2Address(
      _salt(asset),
      address(this),
      type(V4Router).creationCode,
      abi.encode(V4_AGGREGATION_ROUTER, V4_AGGREGATION_EXECUTOR, asset)
    );
  }

  function _computeV5AggregationRouterAddress(address asset) internal view returns (address) {
    return Create2.computeCreate2Address(
      _salt(asset),
      address(this),
      type(V5Router).creationCode,
      abi.encode(V5_AGGREGATION_ROUTER, V5_AGGREGATION_EXECUTOR, asset)
    );
  }

  function _salt(address asset) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(asset)));
  }
}

