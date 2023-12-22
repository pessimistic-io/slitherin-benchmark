// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";

interface ICanister {
  struct UserInfo {
    uint256 amount; // How many tokens the user has provided.
    uint256 lastWithdrawTimestamp; // the last Timestamp a user withdrew at.
    uint256 firstDepositTimestamp; // the first Timestamp a user deposited at.
    uint256 lastDepositTimestamp; // the last Timestamp user depostied at.
    uint256 totalDeposited;
    uint256 totalWithdrawn;
    uint256 rewardDebt;
    uint256 rewardDebtAtTimestamp; // the last Timestamp user stake
    uint256 timestampDelta;
  }

  struct RewardInfo {
    uint256 lastClaimedTimestamp;
    uint256 totalReward;
    uint256 reward;
    uint256 totalClaimed;
  }

  // Info of each pool.
  struct PoolInfo {
    IERC20Upgradeable token; // Address of token contract (BOO, MAGIC, BOO-MAGIC, etc)
    uint256 allocPoint; // How many points are assigned to this pool.
    uint256 balance; // Total tokens locked up
    uint256 rewardPerShare;
    uint256 lastRewardTimestamp;
  }

  // View function to see pending $BOO on frontend.'
  // Add pendingRewards in each pool and claimed rewards in RewardInfo for accuracy
  function getPendingRewards(address _user, address[] memory poolTokens) external view returns (uint256);

  function updatePool(address poolToken) external;

  function getRewardInfo(address _user) external view returns (uint256);

  // User deposit tokens
  function deposit(address _user, address poolToken, uint256 amount) external;
  
  // User withdraws tokens from respective token pools
  function withdraw(address _user, address poolToken, uint256 amount) external;

  function claimRewards(address[] memory poolTokens) external;

  function getWithdrawable(address _user, address[] memory poolTokens) external view returns (uint256);

  function getClaimable(address _user) external view returns (uint256);

  function getLockedReward(address _user) external view returns (uint256);
}
