// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITokenManager {
  function usageAllocations(address userAddress, address usageAddress) external view returns (uint256 allocation);
  function allocateFromUsage(address userAddress, uint256 amount) external;
  function deallocateFromUsage(address userAddress, uint256 amount) external;
  function convertTo(uint256 amount, address to) external;
}

