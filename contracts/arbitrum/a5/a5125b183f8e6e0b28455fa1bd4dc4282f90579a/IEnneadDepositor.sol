// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEnneadDepositor {
    function deposit(address pool, uint256 amount) external;
    function withdraw(address pool, uint256 amount) external;
    function tokenForPool(address pool) external view returns (address);
}

