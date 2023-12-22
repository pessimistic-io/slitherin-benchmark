// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20_IERC20.sol";
import "./IAggregationExecutor.sol";

import { SwapDescription } from "./Types.sol";

interface IAggregationRouterV4 {
    function swap(
        IAggregationExecutor caller,
        SwapDescription calldata desc,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 gasLeft);
}
