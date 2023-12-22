// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IRewardMinter.sol";

contract ASCNStaking is Ownable {
  using SafeERC20 for IERC20;

  uint256 private constant ACC_PRECISION = 1e24;

  struct UserInfo {
    uint256 amount;
    uint256 weightedAmount;
    uint256 rewardDebt;
  }

  struct PoolInfo {
    address stakingToken;
    uint256 startTime;
    uint256 endTime;
    uint256 rewardPerTime;
    uint256 hodlWeightMax;
    uint256 hodlWeightMin;
    bool privatePool;

    uint256 totalAmount;
    uint256 totalWeightedAmount;

    uint256 lastUpdateTime;
    uint256 accRewardPerWeightedAmount_e24;
  }

  IRewardMinter public rewardMinter;

  PoolInfo[] public poolInfos;
  mapping(uint256 => mapping(address => UserInfo)) public userInfos;

  event Stake(address indexed user, uint256 indexed pid, uint256 amount);
  event Unstake(address indexed user, uint256 indexed pid, uint256 amount);
  event Claim(address indexed user, uint256 indexed pid, uint256 amount);

  constructor(IRewardMinter _rewardMinter) {
    require(address(_rewardMinter) != address(0), "ASCNStaking: invalid reward minter");
    rewardMinter = _rewardMinter;
  }

  function numPools() external view returns (uint256) {
    return poolInfos.length;
  }

  function addPool(
    address _stakingToken,
    uint256 _startTime,
    uint256 _endTime,
    uint256 _rewardPerTime,
    uint256 _hodlWeightMax,
    uint256 _hodlWeightMin,
    bool _privatePool
  ) public onlyOwner {
    require(address(_stakingToken) != address(0), "addPool: invalid staking token");
    require(_startTime > block.timestamp, "addPool: invalid start time");
    require(_endTime > _startTime, "addPool: invalid end time");
    require(_rewardPerTime > 0, "addPool: invalid reward per time");
    require(_hodlWeightMax >= _hodlWeightMin, "addPool: invalid hodl weights");

    updateAllPools();
    poolInfos.push(
      PoolInfo({
        stakingToken: _stakingToken,
        startTime: _startTime,
        endTime: _endTime,
        rewardPerTime: _rewardPerTime,
        hodlWeightMax: _hodlWeightMax,
        hodlWeightMin: _hodlWeightMin,
        privatePool: _privatePool,
        totalAmount: 0,
        totalWeightedAmount: 0,
        lastUpdateTime: _startTime,
        accRewardPerWeightedAmount_e24: 0
      })
    );
  }

  function updateAllPools() public {
    uint256 length = poolInfos.length;
    for (uint256 pid = 0; pid < length; pid++) {
      updatePool(pid);
    }
  }

  function updatePool(uint256 _pid) public {
    PoolInfo storage pool = poolInfos[_pid];
    if (block.timestamp <= pool.lastUpdateTime) {
        return;
    }
    if (block.timestamp < pool.startTime) {
        return;
    }
    if (pool.lastUpdateTime >= pool.endTime) {
        return;
    }
    uint256 newUpdateTime = block.timestamp >= pool.endTime ? pool.endTime : block.timestamp;
    if (pool.totalWeightedAmount>0) {
      uint256 poolReward = (newUpdateTime- pool.lastUpdateTime) * pool.rewardPerTime;
      rewardMinter.safeMint(poolReward);
      pool.accRewardPerWeightedAmount_e24 += (poolReward * ACC_PRECISION / pool.totalWeightedAmount);
    }
    pool.lastUpdateTime= newUpdateTime;
  }

  function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo storage pool = poolInfos[_pid];
    UserInfo storage user = userInfos[_pid][_user];
    uint256 accRewardPerWeightedAmount_e24 = pool.accRewardPerWeightedAmount_e24;

    if (
      block.timestamp > pool.lastUpdateTime &&
      block.timestamp >= pool.startTime &&
      pool.lastUpdateTime < pool.endTime &&
      pool.totalWeightedAmount > 0
    ) {
      uint256 newUpdateTime = block.timestamp >= pool.endTime ? pool.endTime : block.timestamp;
      uint256 newReward = (newUpdateTime - pool.lastUpdateTime) * pool.rewardPerTime;
      accRewardPerWeightedAmount_e24 += (newReward * ACC_PRECISION / pool.totalWeightedAmount);
    }
    return (user.weightedAmount * accRewardPerWeightedAmount_e24 / ACC_PRECISION) - user.rewardDebt;
  }

  function stake(address _to, uint256 _pid, uint256 _amount) public {
    require(_to != address(0), "stake: invalid user address");
    require(_amount > 0, "stake: amount must be non-zero");

    PoolInfo storage pool = poolInfos[_pid];
    UserInfo storage user = userInfos[_pid][_to];
    require(!pool.privatePool || msg.sender == owner(), "stake: private pool");

    updatePool(_pid);
    if (user.weightedAmount > 0) {
      uint256 pending = (user.weightedAmount * pool.accRewardPerWeightedAmount_e24 / ACC_PRECISION) - user.rewardDebt;
      rewardMinter.safeRewardTransfer(_to, pending);
    }
    IERC20(pool.stakingToken).safeTransferFrom(
      address(msg.sender),
      address(this),
      _amount
    );
    uint256 weightTime = block.timestamp < pool.startTime ? pool.startTime : block.timestamp;
    uint256 blockMult = pool.endTime - weightTime;
    uint256 poolTime = pool.endTime - pool.startTime;
    uint256 hodlSpread = pool.hodlWeightMax - pool.hodlWeightMin;

    // Divide last to maximize precision
    uint256 weightedAmount = _amount * ((hodlSpread * blockMult) + (poolTime * pool.hodlWeightMin)) / poolTime;

    user.amount += _amount;
    user.weightedAmount += weightedAmount;
    pool.totalAmount += _amount;
    pool.totalWeightedAmount += weightedAmount;

    user.rewardDebt = user.weightedAmount * pool.accRewardPerWeightedAmount_e24 / ACC_PRECISION;
    emit Stake(_to, _pid, _amount);
  }

  function claim(uint256 _pid) public {
    PoolInfo storage pool = poolInfos[_pid];
    UserInfo storage user = userInfos[_pid][msg.sender];
    updatePool(_pid);
    uint256 pending = (user.weightedAmount * pool.accRewardPerWeightedAmount_e24 / ACC_PRECISION) - user.rewardDebt;
    require(pending > 0, "claim: no pending reward");
    user.rewardDebt = user.weightedAmount * pool.accRewardPerWeightedAmount_e24 / ACC_PRECISION;
    rewardMinter.safeRewardTransfer(msg.sender, pending);
    emit Claim(msg.sender, _pid, pending);
  }

  function unstake(uint256 _pid, uint256 _amount) public {
    require(_amount > 0, "unstake: amount must be non-zero");
    PoolInfo storage pool = poolInfos[_pid];
    UserInfo storage user = userInfos[_pid][msg.sender];
    require(user.amount >= _amount, "unstake: invalid amount");
    require(!pool.privatePool || block.timestamp >= pool.startTime, "unstake: too early");
    updatePool(_pid);
    uint256 pending = (user.weightedAmount * pool.accRewardPerWeightedAmount_e24 / ACC_PRECISION) - user.rewardDebt;
    if (pending > 0) {
      user.rewardDebt = user.weightedAmount * pool.accRewardPerWeightedAmount_e24 / ACC_PRECISION;
      rewardMinter.safeRewardTransfer(msg.sender, pending);
    }

    uint256 weightedAmount = (user.weightedAmount * _amount) / user.amount;
    user.amount -= _amount;
    user.weightedAmount -= weightedAmount;
    user.rewardDebt = user.weightedAmount * pool.accRewardPerWeightedAmount_e24 / ACC_PRECISION;

    pool.totalAmount -= _amount;
    pool.totalWeightedAmount -= weightedAmount;
    IERC20(pool.stakingToken).safeTransfer(address(msg.sender), _amount);
  }
}

