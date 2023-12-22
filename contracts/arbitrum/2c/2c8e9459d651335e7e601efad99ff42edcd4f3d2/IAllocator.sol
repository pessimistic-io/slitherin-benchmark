// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAllocator {
    function updateStrategyDebt(uint256 newDebt) external;
}
