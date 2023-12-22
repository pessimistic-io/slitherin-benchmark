// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;

import "./IPool.sol";

interface IPoolFactory {
    function createPool(Config memory config) external returns (address pool);

    function LOGIC() external view returns (address);
}

