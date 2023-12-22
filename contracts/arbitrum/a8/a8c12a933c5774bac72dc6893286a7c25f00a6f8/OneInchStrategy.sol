// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./I1InchStrategy.sol";
import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";
import "./Withdrawable.sol";

contract OneInchStrategy is I1InchStrategy, Withdrawable {
    receive() external payable {}

    function swap(
        address router,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable override returns (uint256 returnAmount, uint256 spentAmount) {
        if (address(desc.srcToken) != address(0)) desc.srcToken.approve(router, desc.amount);
        return I1InchRouter(router).swap{ value: msg.value }(executor, desc, permit, data);
    }
}

