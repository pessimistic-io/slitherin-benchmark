pragma solidity >=0.8.0;

import {IV5AggregationExecutor} from "./IV5AggregationExecutor.sol";
import {IERC20} from "./IERC20.sol";

interface IV5AggregationRouter {
  struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
  }

  function swap(
    IV5AggregationExecutor executor,
    SwapDescription calldata desc,
    bytes calldata permit,
    bytes calldata data
  ) external payable returns (uint256 returnAmount, uint256 spentAmount);
}

