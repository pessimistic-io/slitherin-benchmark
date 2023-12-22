// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IRegistry {
    function getCoinIndices(address _pool, address _from, address _to) external view returns (uint256, uint256);
}

