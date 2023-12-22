// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface ICamelotRouter {
   
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        address referrer,
        uint256 deadline
    ) external;

}
