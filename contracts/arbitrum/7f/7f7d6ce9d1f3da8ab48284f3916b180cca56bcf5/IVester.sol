// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IVester {
    function deposit(uint256 pglAmount) external;
    function withdraw() external;
}
