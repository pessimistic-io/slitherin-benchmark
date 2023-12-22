// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "./IERC20.sol";

import {IV5AggregationExecutor} from "./IV5AggregationExecutor.sol";
import {IV5AggregationRouter} from "./IV5AggregationRouter.sol";
import {AggregationV5BaseRouter} from "./AggregationBaseRouter.sol";

/// @notice A router to swap tokens using 1inch's v5 aggregation router.
contract V5Router is AggregationV5BaseRouter {
  /// @dev Thrown when a function is not supported.
  error UnsupportedFunction();

  constructor(
    IV5AggregationRouter aggregationRouter,
    IV5AggregationExecutor aggregationExecutor,
    address token
  ) AggregationV5BaseRouter(aggregationExecutor, aggregationRouter, token) {
    IERC20(token).approve(address(aggregationRouter), type(uint256).max);
  }

  /// @dev If we remove this function solc will give a missing-receive-ether warning because we have
  /// a payable fallback function. We cannot change the fallback function to a receive function
  /// because receive does not have access to msg.data. In order to prevent a missing-receive-ether
  /// warning we add a receive function and revert.
  receive() external payable {
    revert UnsupportedFunction();
  }

  // Flags match specific constant masks. There is no documentation on these.
  fallback() external payable {
    address dstToken = address(bytes20(msg.data[0:20]));
    uint256 amount = uint256(uint96(bytes12(msg.data[20:32])));
    uint256 minReturnAmount = uint256(uint96(bytes12(msg.data[32:44])));
    uint256 flags = uint256(uint8(bytes1(msg.data[44:45])));
    bytes memory data = bytes(msg.data[45:msg.data.length]);

    IERC20(TOKEN).transferFrom(msg.sender, address(this), amount);
    AGGREGATION_ROUTER.swap(
      AGGREGATION_EXECUTOR,
      IV5AggregationRouter.SwapDescription({
        srcToken: IERC20(TOKEN),
        dstToken: IERC20(dstToken),
        srcReceiver: payable(SOURCE_RECEIVER),
        dstReceiver: payable(msg.sender),
        amount: amount,
        minReturnAmount: minReturnAmount,
        flags: flags
      }),
      "",
      data
    );
  }
}

