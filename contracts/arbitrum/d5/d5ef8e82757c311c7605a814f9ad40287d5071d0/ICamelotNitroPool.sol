// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";

interface ICamelotNitroPool {
  struct RewardsToken {
    IERC20 token;
    uint256 amount; // Total rewards to distribute
    uint256 remainingAmount; // Remaining rewards to distribute
    uint256 accRewardsPerShare;
  }
  function withdraw(uint256 tokenId) external;
  function harvest() external;
  function pendingRewards(address account) external view returns (uint256 pending1, uint256 pending2);
  function rewardsToken1() external view returns (RewardsToken calldata rewardsToken);
  function rewardsToken2() external view returns (RewardsToken calldata rewardsToken);
}

