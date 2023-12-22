pragma solidity >=0.8.0;

import {IV4AggregationExecutor} from "./IV4AggregationExecutor.sol";
import {IERC20} from "./IERC20.sol";

interface IV4AggregationRouter {
  struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
    bytes permit;
  }

  function swap(IV4AggregationExecutor executor, SwapDescription calldata desc, bytes calldata data)
    external
    payable
    returns (uint256 returnAmount, uint256 spentAmount, uint256 gasLeft);
}

