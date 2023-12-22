// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./IERC20BurnableMinter.sol";
import "./IBank.sol";

// The stakepool will mint prLab according to the total supply of Lab and
// then distribute it to all users according to the amount of Lab deposited by each user.
// Info of each pool.
struct PoolInfo {
  IERC20 lpToken; // Address of LP token contract.
  uint256 allocPoint; // How many allocation points assigned to this pool. prLabs to distribute per block.
  uint256 lastRewardBlock; // Last block number that prLabs distribution occurs.
  uint256 accPerShare; // Accumulated prLabs per share, times 1e12. See below.
}

// Info of each user.
struct UserInfo {
  uint256 amount; // How many LP tokens the user has provided.
  uint256 rewardDebt; // Reward debt. See explanation below.
  //
  // We do some fancy math here. Basically, any point in time, the amount of prLabs
  // entitled to a user but is pending to be distributed is:
  //
  //   pending reward = (user.amount * pool.accPerShare) - user.rewardDebt
  //
  // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
  //   1. The pool's `accPerShare` (and `lastRewardBlock`) gets updated.
  //   2. User receives the pending reward sent to his/her address.
  //   3. User's `amount` gets updated.
  //   4. User's `rewardDebt` gets updated.
}

interface IStakePool {
  // The Lab token
  function Lab() external view returns (IERC20);

  // The prLab token
  function prLab() external view returns (IERC20BurnableMinter);

  // The bank contract address
  function bank() external view returns (IBank);

  // Info of each pool.
  function poolInfo(uint256 index)
    external
    view
    returns (
      IERC20,
      uint256,
      uint256,
      uint256
    );

  // Info of each user that stakes LP tokens.
  function userInfo(uint256 pool, address user)
    external
    view
    returns (uint256, uint256);

  // Total allocation poitns. Must be the sum of all allocation points in all pools.
  function totalAllocPoint() external view returns (uint256);

  // Daily minted Lab as a percentage of total supply, the value is mintPercentPerDay / 1000.
  function mintPercentPerDay() external view returns (uint32);

  // How many blocks are there in a day.
  function blocksPerDay() external view returns (uint256);

  // Developer address.
  function dev() external view returns (address);

  // Withdraw fee(Lab).
  function withdrawFee() external view returns (uint32);

  // Mint fee(prLab).
  function mintFee() external view returns (uint32);

  // Constructor.
  function constructor1(
    IERC20 _Lab,
    IERC20BurnableMinter _prLab,
    IBank _bank,
    address _owner
  ) external;

  function poolLength() external view returns (uint256);

  // Add a new lp to the pool. Can only be called by the owner.
  // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  function add(
    uint256 _allocPoint,
    IERC20 _lpToken,
    bool _withUpdate
  ) external;

  // Update the given pool's prLab allocation point. Can only be called by the owner.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) external;

  // Set options. Can only be called by the owner.
  function setOptions(
    uint32 _mintPercentPerDay,
    uint256 _blocksPerDay,
    address _dev,
    uint32 _withdrawFee,
    uint32 _mintFee,
    bool _withUpdate
  ) external;

  // View function to see pending prLabs on frontend.
  function pendingRewards(uint256 _pid, address _user)
    external
    view
    returns (uint256);

  // Update reward vairables for all pools. Be careful of gas spending!
  function massUpdatePools() external;

  // Deposit LP tokens to StakePool for prLab allocation.
  function deposit(uint256 _pid, uint256 _amount) external;

  // Deposit LP tokens to StakePool for user for prLab allocation.
  function depositFor(
    uint256 _pid,
    uint256 _amount,
    address _user
  ) external;

  // Withdraw LP tokens from StakePool.
  function withdraw(uint256 _pid, uint256 _amount) external;

  // Claim reward.
  function claim(uint256 _pid) external;

  // Claim reward for user.
  function claimFor(uint256 _pid, address _user) external;
}

