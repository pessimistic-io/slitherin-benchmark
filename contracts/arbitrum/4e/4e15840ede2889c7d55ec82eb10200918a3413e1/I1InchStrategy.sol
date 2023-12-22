// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";

interface I1InchStrategy {
    function swap(
        address router,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 returnAmount, uint256 spentAmount);
}

