// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IPoolFactory {
    function createPool(address _pool, address _reward) external returns (address);
}

