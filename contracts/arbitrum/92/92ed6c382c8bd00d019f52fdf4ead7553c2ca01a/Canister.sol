// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./ICanister.sol";
import "./ITreasury.sol";
import "./CanisterBase.sol";

contract Canister is Initializable,
  ICanister,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  CanisterBase {

  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  EnumerableSetUpgradeable.AddressSet private pools;

  modifier onlyAuthorized() {
      require(authorized[msg.sender] || owner() == msg.sender, "caller is not authorized");
      _;
  }

  modifier poolExists(address poolToken) {
    require(pools.contains(poolToken), "Pool does not exist");
    _;
  }

  modifier canisterActive(address poolToken) {
    require(endTimestamp > block.timestamp, "Canister reward ended");
    _;
  }

  function initialize(
    address _boo, 
    address _treasury,
    uint256 _totalReward, 
    uint256 _startTimestamp, 
    uint256 _endTimestamp, 
    uint256 _initialUnlock, 
    address _devaddr,
    uint256[] memory _withdrawalFees) public initializer {
      __Ownable_init();
      __ReentrancyGuard_init();
      boo = IERC20Upgradeable(_boo);
      treasury = ITreasury(_treasury);
      startTimestamp = _startTimestamp;
      initialUnlock = _initialUnlock;
      totalReward = _totalReward;
      ratePerSecond = _totalReward / (_endTimestamp - _startTimestamp);
      devaddr = _devaddr;
      withdrawalFees = _withdrawalFees;
  }

  // View function to see pending $BOO on frontend.'
  // Add pendingRewards in each pool and claimed rewards in RewardInfo for accuracy
  function getPendingRewards(address _user, address[] memory poolTokens) public view returns (uint256) {
      uint256 reward = 0;
      for (uint256 i=0; i<poolTokens.length; i++) {
          reward = reward + getPendingReward(_user, poolTokens[i]);
      }
      return reward;
  }

  // Returns pendingReward in a pool
  function getPendingReward(address _user, address poolToken) public view returns (uint256) {
      if (block.timestamp < startTimestamp) return 0;
      UserInfo storage user = userInfo[poolToken][_user];
      PoolInfo storage pool = poolInfo[poolToken];
      uint256 rewardPerShare = pool.rewardPerShare;

      if (block.timestamp > pool.lastRewardTimestamp && pool.balance > 0) {
          uint256 pendingReward = ratePerSecond * (block.timestamp - pool.lastRewardTimestamp);
          uint256 reward = (pendingReward * pool.allocPoint) / totalAllocPoint;
          rewardPerShare = rewardPerShare + (reward * 1 ether / pool.balance);
      }
      return (user.amount * rewardPerShare / 1 ether) - user.rewardDebt;
  }

  function updatePool(address poolToken) public poolExists(poolToken) {
      PoolInfo storage pool = poolInfo[poolToken];
      if (block.timestamp <= pool.lastRewardTimestamp) return;

      uint256 supply = pool.balance;
      if (supply == 0) {
          pool.lastRewardTimestamp = block.timestamp;
          return;
      }
      treasury.requestFund();
      uint256 pendingReward = ratePerSecond * (block.timestamp - pool.lastRewardTimestamp);
      uint256 reward = (pendingReward * pool.allocPoint) / totalAllocPoint;
      pool.rewardPerShare = pool.rewardPerShare + (reward * 1 ether / supply);
      pool.lastRewardTimestamp = block.timestamp;
      emit Update(poolToken, pool.rewardPerShare, pool.lastRewardTimestamp);
  }

  function _harvest(address poolToken) internal {
      PoolInfo storage pool = poolInfo[poolToken];
      UserInfo storage user = userInfo[poolToken][msg.sender];

      if (user.amount > 0) {
          uint256 pending = (user.amount * pool.rewardPerShare / 1 ether) - user.rewardDebt;
          if (pending > 0) {
              // boo.transfer(msg.sender, pending);
              // Reset the rewardDebtAtBlock to the current block for the user.
              RewardInfo storage _reward = rewardInfo[msg.sender];
              _reward.totalReward =  _reward.totalReward + pending;
              _reward.reward += pending;
              user.rewardDebtAtTimestamp = block.timestamp; 
              emit SendReward(msg.sender, poolToken, pending);
          }
          // Recalculate the rewardDebt for the user.
          user.rewardDebt = user.amount * pool.rewardPerShare / 1 ether;
      }
  }

  function getRewardInfo(address _user) public view returns (uint256) {
    return rewardInfo[_user].reward;
  }

  // User deposit tokens
  function deposit(address _user, address poolToken, uint256 amount) public poolExists(poolToken) nonReentrant {
    UserInfo storage user = userInfo[poolToken][_user];
    PoolInfo storage pool = poolInfo[poolToken];
    IERC20Upgradeable token = IERC20Upgradeable(poolToken);
    // When a user deposits, we need to update the pool and harvest beforehand,
    // since the rates will change.
    updatePool(poolToken);
    _harvest(poolToken);

    token.safeTransferFrom(msg.sender, address(this), amount);
    user.amount += amount;
    user.totalDeposited += amount;
    pool.balance += amount;
    if (user.amount == 0) {
        user.rewardDebtAtTimestamp = block.timestamp;
    }
    user.rewardDebt = user.amount * pool.rewardPerShare / 1 ether;
    if (user.firstDepositTimestamp > 0) {} else {
        user.firstDepositTimestamp = block.timestamp;
    }
    user.lastDepositTimestamp = block.timestamp;
    emit Deposit(_user, poolToken, amount);
  }

  function addRewardToUser(address _user, uint256 amount) external onlyAuthorized {
    RewardInfo storage _reward = rewardInfo[msg.sender];
    _reward.totalReward =  _reward.totalReward + amount;
    _reward.reward += amount;
    emit RewardAddedToUser(msg.sender, _user, amount);
  }

  function claimRewards(address[] memory poolTokens) public {
    for (uint256 i = 0; i < poolTokens.length; i++) {
      updatePool(poolTokens[i]);
      _harvest(poolTokens[i]);
    }
    RewardInfo storage user = rewardInfo[msg.sender];
    // uint256 amount = user.totalReward;
    uint256 amount = getUnlocked(user.reward, user.totalReward, user.totalClaimed);

    if (pools.contains(address(boo))) {
      if (amount > boo.balanceOf(address(this)) - poolInfo[address(boo)].balance) {
        amount = boo.balanceOf(address(this)) - poolInfo[address(boo)].balance;
      }
    } else {
      if (amount > boo.balanceOf(address(this))) {
        amount = boo.balanceOf(address(this));
      }
    }

    user.reward -= amount;
    user.totalClaimed += amount;
    boo.safeTransfer(msg.sender, amount);
    emit RewardClaimed(msg.sender, amount);
  }

  function getWithdrawable(address _user, address[] memory poolTokens) public view returns (uint256) {
    uint256 amount;
    for (uint256 i = 0; i < poolTokens.length; i++) {
      UserInfo storage user = userInfo[poolTokens[i]][_user];
      amount += getUnlocked(user.amount, user.totalDeposited, user.totalWithdrawn);
    }
    return amount;
  }

  function getClaimable(address _user) public view returns (uint256) {
    RewardInfo storage user = rewardInfo[_user];
    return getUnlocked(user.reward, user.totalReward, user.totalClaimed);
  }

  function getLockedReward(address _user) public view returns (uint256) {
    RewardInfo storage user = rewardInfo[_user];
    return user.reward - getUnlocked(user.reward, user.totalReward, user.totalClaimed);
  }

  // Returns unlocked token amount that users can withdraw
  function getUnlocked(uint256 current, uint256 total, uint256 claimed) internal view returns (uint256) {
    if (block.timestamp < startTimestamp) {
      return  0;
    } else if (block.timestamp >= endTimestamp) {
      return current;
    }
    uint256 releaseBlock =  block.timestamp - startTimestamp;
    uint256 totalLockedBlock = endTimestamp - startTimestamp;
    uint256 initialUnlockScale = 100 - initialUnlock;
    uint256 unlockedTotalDeposited = (total * (((releaseBlock * 1e5 * initialUnlockScale) / totalLockedBlock / 100) + (initialUnlock * 1e5 / 100))) / 1e5;
    if (claimed >= total) return 0;
    else return unlockedTotalDeposited - claimed;
  }

  // User withdraws tokens from respective token pools
  function withdraw(address _user, address poolToken, uint256 amount) public poolExists(poolToken) nonReentrant {
    require(msg.sender == _user, "Only owner can withdraw");
    UserInfo storage user = userInfo[poolToken][_user];
    PoolInfo storage pool = poolInfo[poolToken];
    require(amount <= getUnlocked(user.amount, user.totalDeposited, user.totalWithdrawn), "Given amount is not unlocked yet");
    updatePool(poolToken);
    _harvest(poolToken);
    if (amount > 0) {
      user.amount = user.amount - amount;
      if (user.lastWithdrawTimestamp > 0) {
        user.timestampDelta = block.timestamp - user.lastWithdrawTimestamp;
      } else {
        user.timestampDelta = block.timestamp - user.firstDepositTimestamp;
      }
      //25% fee for withdrawals of tokens in the same block to prevent abuse from flashloans
      if (user.timestampDelta == withdrawalFees[0] || block.timestamp == user.lastWithdrawTimestamp) {
        uint256 fees = (amount * 25) / 100;
        pool.token.transfer(msg.sender, amount - fees);
        pool.token.transfer(address(devaddr), fees);
      } else if (user.timestampDelta > withdrawalFees[0] && user.timestampDelta <= withdrawalFees[1]) {
        //10% fee if a user deposits and withdraws in between same block and 59 minutes.
        uint256 fees = (amount * 10) / 100;
        pool.token.safeTransfer(msg.sender, amount - fees);
        pool.token.safeTransfer(address(devaddr), fees);
      } else {
        pool.token.transfer(msg.sender, amount);
      }
      user.rewardDebt = user.amount * pool.rewardPerShare / 1 ether;
      user.lastWithdrawTimestamp = block.timestamp;
      pool.balance -= amount;
      user.totalWithdrawn += amount;
      emit Withdraw(msg.sender, poolToken, amount);
    } 
  }

  function addPool(address poolToken, uint256 _allocPoint) public onlyAuthorized {
    require(pools.contains(poolToken) == false, "Token already allocated for canister");
    totalAllocPoint += _allocPoint;
    uint256 lastRewardTimestamp =
    block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
    if (pools.add(poolToken)) {
      poolInfo[poolToken] = PoolInfo({
        token: IERC20Upgradeable(poolToken),
        allocPoint: _allocPoint,
        balance: 0,
        lastRewardTimestamp: lastRewardTimestamp,
        rewardPerShare: 0
      });
      emit PoolAdded(poolToken, _allocPoint);
    }
  }

  function setPool(address poolToken, uint256 _allocPoint) public onlyAuthorized poolExists(poolToken) {
    totalAllocPoint = totalAllocPoint - poolInfo[poolToken].allocPoint + _allocPoint;
    poolInfo[poolToken].allocPoint = _allocPoint;
    emit PoolUpdated(poolToken, _allocPoint);
  }

  
  function removePool(address poolToken)
      external
      virtual
      onlyAuthorized
      poolExists(poolToken)
  {
      if (poolInfo[poolToken].balance == 0 && pools.remove(poolToken)) {
          totalAllocPoint -= poolInfo[poolToken].allocPoint;
          delete poolInfo[poolToken];
          emit PoolRemoved(poolToken);
      }
  }

  function poolLength() external view returns (uint256) {
    return pools.length();
  }

  function getPoolBalance(address poolToken) public view returns (uint256) {
    return poolInfo[poolToken].balance;
  }

  function getUserBalance(address poolToken, address _user) public view returns (uint256) {
    return userInfo[poolToken][_user].amount;
  }

  function addAuthorized(address _toAdd) public onlyOwner {
      authorized[_toAdd] = true;
  }

  function removeAuthorized(address _toRemove) public onlyOwner {
      require(_toRemove != msg.sender);
      authorized[_toRemove] = false;
  }

  function setInitialUnlock(uint256 _initialUnlock) public onlyAuthorized {
      require(_initialUnlock < 100);
      initialUnlock = _initialUnlock;
  }

 function updateTimestamp(uint256 _startTimestamp, uint256 _endTimestamp)
        external
        onlyAuthorized
    {

        if (_startTimestamp > 0) {
            require(_startTimestamp > block.timestamp, "startTimestamp cannot be in the past");

            startTimestamp = _startTimestamp;
        }

        if (_endTimestamp > 0) {
            require(_endTimestamp > _startTimestamp, "Rewards must last > 1 sec");
            require(_endTimestamp > block.timestamp, "Cannot end rewards in the past");

            endTimestamp = _endTimestamp;
        }

        ratePerSecond = totalReward / (endTimestamp - startTimestamp);

    }
  
  function setTotalReward(uint256 amount) external onlyAuthorized {
    totalReward = amount;
    ratePerSecond = totalReward / (endTimestamp - startTimestamp);
  }

  function setWithdrawalFeeStages(uint256[] memory _userFees) public onlyAuthorized {
      withdrawalFees = _userFees;
  }
}

