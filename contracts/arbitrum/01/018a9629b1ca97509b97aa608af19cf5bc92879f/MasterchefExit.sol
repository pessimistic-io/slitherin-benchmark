// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import { IERC20 } from "./SafeERC20.sol";
import { AMasterchefBase } from "./AMasterchefBase.sol";

contract MasterchefExit is AMasterchefBase {
  constructor(address rewardToken_, uint256 rewardsDuration_) AMasterchefBase(rewardToken_, rewardsDuration_) {}

  event UpdateRewards(address indexed caller, uint256 amount);
  event StopRewards(uint256 undistributedRewards);

  function deposit(uint256 pid, uint256 amount) public override {
    PoolInfo storage pool = poolInfo[pid];
    UserInfo storage user = userInfo[pid][msg.sender];
    _requireNonZeroAmount(amount);
    _updatePool(pool);

    /// @dev Undistributed rewards to this pool are given to the first staker.
    if (pool.totalStaked == 0) {
      _safeClaimRewards(pid, pool.accUndistributedReward / PRECISION);
      pool.accUndistributedReward = 0;
    } else {
      _safeClaimRewards(pid, _getUserPendingReward(user.amount, user.rewardDebt, pool.accRewardPerShare));
    }

    _transferAmountIn(pool.token, amount);
    user.amount += amount;
    user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;
    pool.totalStaked += amount;

    emit Deposit(msg.sender, pid, amount);
  }

  function updateRewards(uint256 amount) external override onlyOwner {
    // Updates pool to account for the previous rewardRate.
    _massUpdatePools();

    _requireNonZeroAmount(amount);
    require(totalAllocPoint != 0, 'MasterchefExit: Must add a pool prior to adding rewards');
    require(rewardRate == 0, 'MasterchefExit: Can only deposit rewards once');
    require(IERC20(REWARD_TOKEN).balanceOf(address(this)) >= amount, 'MasterchefExit: Token balance not sufficient');
    rewardRate = (amount * PRECISION) / REWARDS_DURATION;
    periodFinish = block.timestamp + REWARDS_DURATION;
    emit UpdateRewards(msg.sender, amount, rewardRate, periodFinish);
  }

  function stopRewards(uint256 allocatedRewards) external onlyOwner returns (uint256 undistributedRewards) {
    if (rewardRate == 0) return 0; // rewards have not been allocated
    if (block.timestamp < periodFinish) {
      unchecked {
        uint256 rewardStartTime = periodFinish - REWARDS_DURATION;
        uint256 distributedRewards = ((block.timestamp - rewardStartTime) * rewardRate) / PRECISION;
        undistributedRewards = allocatedRewards - distributedRewards;
      }
      periodFinish = block.timestamp;
    }
    emit StopRewards(undistributedRewards);
  }

  function _requireNonZeroAmount(uint256 _amount) internal pure {
    require(_amount != 0, 'MasterchefExit: Amount must not be zero');
  }
}

