// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategy {
   function createStrategy(uint256 _strategyID,uint256 _plotID) external returns (uint256);
}

