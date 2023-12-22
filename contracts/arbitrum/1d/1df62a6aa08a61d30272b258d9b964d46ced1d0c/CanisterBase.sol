// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./ITreasury.sol";
import "./IERC20Upgradeable.sol";
import "./ICanister.sol";
import "./EnumerableSetUpgradeable.sol";


contract CanisterBase {
  mapping(address => bool) public authorized;
  ITreasury treasury;
  uint256 public totalReward;
  uint256 public startTimestamp;
  uint256 public endTimestamp;
  uint256 public ratePerSecond;

  IERC20Upgradeable public boo;
  // Owner address; Withdrawal fees would go to this address
  address public devaddr;

  uint256 public totalAllocPoint;

  uint256 public initialUnlock; // In percentage, e.g 25 for 25%

  uint256[] public withdrawalFees;

  mapping (address => ICanister.PoolInfo) public poolInfo;

  // poolTokenAddress => userAddress => UserInfo
  mapping(address => mapping(address => ICanister.UserInfo)) public userInfo; // poolId => userAddress => UserInfo
  mapping(address => ICanister.RewardInfo) public rewardInfo; // userAddress => RewardInfo

  event Update(address indexed poolToken, uint256 rewardPerShare, uint256 lastRewardBlock);
  event FundDifference(address indexed poolToken, uint256 blockTimestamp, uint256 lastRewardTimestamp, uint256 pulledFund, uint256 pendingReward);
  event Deposit(address indexed user, address indexed poolToken, uint256 amount);
  event SendReward(address indexed user, address indexed poolToken, uint256 reward);
  event RewardClaimed(address indexed user, uint256 reward);
  event Withdraw(address indexed user, address indexed poolToken, uint256 amount);
  event PoolAdded(address indexed poolToken, uint256 allocPoint);
  event PoolUpdated(address indexed poolToken, uint256 allocPoint);
  event PoolRemoved(address indexed poolToken);
  event RewardAddedToUser(address indexed sender, address indexed receiver, uint256 amount);
}

