// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IGmxRouter {
  function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external returns (uint256);
} 

