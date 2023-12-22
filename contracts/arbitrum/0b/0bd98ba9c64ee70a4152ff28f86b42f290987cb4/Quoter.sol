// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface Quoter {
    function quoteExactInput(bytes memory _path, uint256 amountIn) external returns ( uint256 amountOut, uint160[] memory afterSqrtPList, uint32[] memory initializedTicksCrossedList, int256 gasEstimate);
}
