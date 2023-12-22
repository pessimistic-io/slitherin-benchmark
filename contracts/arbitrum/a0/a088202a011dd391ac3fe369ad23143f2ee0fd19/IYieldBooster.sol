// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IYieldBooster {
  function deallocateAllFromPool(address userAddress, uint256 tokenId) external;
  function getMultiplier(address poolAddress, uint256 maxBoostMultiplier, uint256 amount, uint256 totalPoolSupply, uint256 allocatedAmount) external view returns (uint256);
  function getExpectedMultiplier(uint256 maxBoostMultiplier, uint256 lpAmount, uint256 totalLpSupply, uint256 userAllocation, uint256 poolTotalAllocation) external view returns (uint256);
  function getUserTotalAllocation(address user) external view returns (uint256);
  function getPoolTotalAllocation(address pool) external view returns (uint256);
  function getUserPositionAllocation(address user, address pool, uint256 tokenId) external view returns(uint256);
}
