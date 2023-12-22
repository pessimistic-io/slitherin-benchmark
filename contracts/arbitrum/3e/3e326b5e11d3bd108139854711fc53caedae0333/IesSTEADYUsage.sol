// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IesSTEADYUsage {
  function allocate(address userAddress, uint256 amount, bytes calldata data) external;
  function deallocate(address userAddress, uint256 amount, bytes calldata data) external;
}

