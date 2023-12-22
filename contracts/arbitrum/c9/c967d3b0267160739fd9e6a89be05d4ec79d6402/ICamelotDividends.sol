// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotDividends {
  function harvestAllDividends() external;

  function usersAllocation(address user) external view returns (uint256);

  function pendingDividendsAmount(address tokenReward, address user) external view returns (uint256);
}

