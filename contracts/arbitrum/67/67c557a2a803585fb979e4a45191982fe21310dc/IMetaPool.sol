// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ISwapPool.sol";

interface IMetaPool is ISwapPool {
    function exchangeUnderlying(uint256 i, uint256 j, uint256 dx, uint256 minDy) external returns (uint256, uint256);
}

