// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IArbSys.sol";

contract CheeseDepositPool is Ownable {
  using SafeERC20 for ERC20;
  struct UserInfo {
    uint256 amount;
    uint256 lastTokenPerShare;
  }

  struct PoolInfo {
    ERC20 lpToken;
    uint256 lpSupply;
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accTokenPerShare;
  }

  PoolInfo[] public poolList;
  mapping(uint256 => mapping(address => UserInfo)) public userInfoMap;

  uint256 public tokenPerBlock;
  uint256 public totalSupply;
  uint256 public totalSupplyAll;
  uint256 public totalAllocPoint;
  ERC20 public immutable arb;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  constructor(address erc20) {
    arb = ERC20(erc20);
  }

  function blockNumber() internal view returns (uint256) {
    // return block.number;
    return IArbSys(0x0000000000000000000000000000000000000064).arbBlockNumber();
  }

  function massUpdatePools() public {
    uint256 length = poolList.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid);
    }
  }

  function addPool(ERC20 lpToken) public onlyOwner {
    require(address(lpToken) != address(0), 'lpToken is zero address');
    uint256 bkn = blockNumber();
    poolList.push(PoolInfo({ lpToken: lpToken, lpSupply: 0, allocPoint: 0, lastRewardBlock: bkn, accTokenPerShare: 0 }));
  }

  function setTokenPerBlock(uint256 _tokenPerBlock) public onlyOwner {
    massUpdatePools();
    tokenPerBlock = _tokenPerBlock;
  }

  function setPoolAllocPoint(uint256 pid, uint256 allocPoint) public onlyOwner {
    require(poolList.length > pid, 'pool not exist');
    massUpdatePools();
    totalAllocPoint = (totalAllocPoint - poolList[pid].allocPoint) + allocPoint;
    poolList[pid].allocPoint = allocPoint;
  }

  function pendingToken(uint256 pid, address account) public view returns (uint256) {
    if (poolList.length <= pid) return 0;
    PoolInfo storage pool = poolList[pid];
    UserInfo storage user = userInfoMap[pid][account];

    if (user.amount == 0) return 0;
    uint256 accTokenPerShare = pool.accTokenPerShare;
    uint256 bkn = blockNumber();
    if (bkn > pool.lastRewardBlock && pool.lpSupply != 0) {
      uint256 tokenReward = ((bkn - pool.lastRewardBlock) * tokenPerBlock * pool.allocPoint) / totalAllocPoint;
      if (totalSupply < tokenReward) tokenReward = totalSupply;
      accTokenPerShare += (tokenReward * 1e12) / pool.lpSupply;
    }
    return (user.amount * (accTokenPerShare - user.lastTokenPerShare)) / 1e12;
  }

  function updatePool(uint256 pid) public {
    PoolInfo storage pool = poolList[pid];
    uint256 bkn = blockNumber();
    if (bkn <= pool.lastRewardBlock) return;
    uint256 diff = bkn - pool.lastRewardBlock;
    pool.lastRewardBlock = bkn;

    if (pool.allocPoint == 0) return;
    if (pool.lpSupply == 0) return;

    uint256 tokenReward = (diff * tokenPerBlock * pool.allocPoint) / totalAllocPoint;
    if (tokenReward > 0) {
      if (totalSupply < tokenReward) tokenReward = totalSupply;
      unchecked {
        totalSupply -= tokenReward;
      }
      pool.accTokenPerShare += (tokenReward * 1e12) / pool.lpSupply;
    }
  }

  function claim(uint256 pid) public returns (uint256) {
    updatePool(pid);
    PoolInfo storage pool = poolList[pid];
    UserInfo storage user = userInfoMap[pid][msg.sender];
    uint256 pending = (user.amount * (pool.accTokenPerShare - user.lastTokenPerShare)) / 1e12;
    user.lastTokenPerShare = pool.accTokenPerShare;
    if (pending > 0) {
      arb.transfer(msg.sender, pending);
    }
    return pending;
  }

  function claimAll() public {
    for (uint256 pid = 0; pid < poolList.length; ++pid) {
      if (userInfoMap[pid][msg.sender].amount > 0) {
        claim(pid);
      }
    }
  }

  function deposit(uint256 pid, uint256 amount) public {
    claim(pid);
    PoolInfo storage pool = poolList[pid];
    UserInfo storage user = userInfoMap[pid][msg.sender];
    uint256 bakBalance = pool.lpToken.balanceOf(address(this));
    pool.lpToken.safeTransferFrom(address(msg.sender), address(this), amount);
    amount = pool.lpToken.balanceOf(address(this)) - bakBalance;
    pool.lpSupply += amount;
    user.amount += amount;

    emit Deposit(msg.sender, pid, amount);
  }

  function withdraw(uint256 pid, uint256 lpAmount) public {
    claim(pid);
    PoolInfo storage pool = poolList[pid];
    UserInfo storage user = userInfoMap[pid][msg.sender];
    require(user.amount >= lpAmount, 'withdraw amount exceeds balance');

    if (lpAmount > 0) {
      user.amount -= lpAmount;
      pool.lpSupply -= lpAmount;

      pool.lpToken.safeTransfer(msg.sender, lpAmount);
    }
    emit Withdraw(msg.sender, pid, lpAmount);
  }

  function emergencyWithdraw(uint256 pid) public {
    PoolInfo storage pool = poolList[pid];
    UserInfo storage user = userInfoMap[pid][msg.sender];
    uint256 amount = user.amount;
    require(amount > 0, 'no deposit');
    user.amount = 0;
    user.lastTokenPerShare = 0;
    if (pool.lpSupply < amount) amount = pool.lpSupply;
    unchecked {
      pool.lpSupply -= amount;
    }
    pool.lpToken.safeTransfer(msg.sender, amount);
    emit EmergencyWithdraw(msg.sender, pid, amount);
  }

  function totalSupplyInc(uint256 amount) public {
    require(amount > 0, 'no amount');
    totalSupply += amount;
    totalSupplyAll += amount;
    arb.transferFrom(msg.sender, address(this), amount);
  }

  function poolLength() external view returns (uint256) {
    return poolList.length;
  }

  function getPoolList() external view returns (PoolInfo[] memory) {
    return poolList;
  }

  function getUserInfoMap(uint256 pid, address _user) external view returns (UserInfo memory) {
    return userInfoMap[pid][_user];
  }

  function getUserInfos(address _user) external view returns (UserInfo[] memory) {
    UserInfo[] memory userInfos = new UserInfo[](poolList.length);
    for (uint256 pid = 0; pid < poolList.length; ++pid) {
      userInfos[pid] = userInfoMap[pid][_user];
    }
    return userInfos;
  }

  function getPendings(address _user) external view returns (uint256[] memory) {
    uint256[] memory pendings = new uint256[](poolList.length);
    for (uint256 pid = 0; pid < poolList.length; ++pid) {
      pendings[pid] = pendingToken(pid, _user);
    }
    return pendings;
  }

  function withdraw(address to, uint256 amount) external onlyOwner {
    require(to != address(0), 'withdraw to zero address');
    require(amount <= totalSupply, 'withdraw amount exceeds balance');
    totalSupply -= amount;
    totalSupplyAll -= amount;

    arb.transfer(to, amount);
  }
}

