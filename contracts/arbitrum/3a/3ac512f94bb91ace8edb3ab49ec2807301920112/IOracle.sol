// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IUnsafeOracle {
    function quotePrice(uint32 secondsAgo) external view returns (uint amountOut);
}
