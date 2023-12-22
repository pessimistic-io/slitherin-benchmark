// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

interface ITWAPRelayer {
    struct SellParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        bool wrapUnwrap;
        address to;
        uint32 submitDeadline;
    }

    function sell(SellParams memory sellParams) external payable returns (uint256 orderId);
}

