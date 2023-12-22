// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotDividends {
  function harvestAllDividends() external;
  function dividendsInfo(address user) external view returns (
    uint256 currentDistributionAmount,
    uint256 currentCycleDistributedAmount,
    uint256 pendingAmount,
    uint256 distributedAmount,
    uint256 accDividendsPerShare,
    uint256 lastUpdateTime,
    uint256 cycleDividendsPercent,
    bool distributionDisabled
  );
  function usersAllocation(address user) external view returns (uint256);
  function pendingDividendsAmount(address tokenReward, address user) external view returns (uint256);
}

