// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IRouterUniV2 {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external;
}

