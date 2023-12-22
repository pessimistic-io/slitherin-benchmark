// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IxGMBLToken {
  function usageAllocations(address userAddress) external view returns (uint256 allocation);

  function allocateFromUsage(address userAddress, uint256 amount) external;
  function convertTo(uint256 amount, address to) external;
  function deallocateFromUsage(address userAddress, uint256 amount) external;

  function isTransferWhitelisted(address account) external view returns (bool);
  function getGMBL() external view returns (address);
}
