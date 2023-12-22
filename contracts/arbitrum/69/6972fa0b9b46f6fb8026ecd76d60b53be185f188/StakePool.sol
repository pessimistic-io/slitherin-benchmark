// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IERC20BurnableMinter.sol";
import "./IStakePool.sol";
import "./IBank.sol";

// The stakepool will mint prLab according to the total supply of Lab and
// then distribute it to all users according to the amount of Lab deposited by each user.
contract StakePool is Ownable {
  using SafeERC20 for IERC20;

bool bankSet = false;
  // The Lab token
  IERC20 public Lab;
  // The prLab token
  IERC20BurnableMinter public prLab;
  // The bank contract
  IBank public bank;
  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes LP tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  // Total allocation poitns. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint = 0;

  // Daily minted Lab as a percentage of Lab total supply.
  uint32 public mintPercentPerDay = 0;
  // How many blocks are there in a day.
  uint256 public blocksPerDay = 0;

  // Developer address.
  address public dev;
  // Withdraw fee(Lab).
  uint32 public withdrawFee = 0;
  // Mint fee(prLab).
  uint32 public mintFee = 0;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

  event Withdraw(
    address indexed user,
    uint256 indexed pid,
    uint256 amount,
    uint256 fee
  );

  event OptionsChanged(
    uint32 mintPercentPerDay,
    uint256 blocksPerDay,
    address dev,
    uint32 withdrawFee,
    uint32 mintFee
  );

  // Constructor.
  constructor(IERC20 _Lab, IERC20BurnableMinter _prLab) {
    Lab = _Lab;
    prLab = _prLab;
  }

  function setBank(IBank _bank) external onlyOwner {
    require(!bankSet, "AlreadySet");
    bank = _bank;
    bankSet = true;
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  // Add a new lp to the pool. Can only be called by the owner.
  // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  function add(
    uint256 _allocPoint,
    IERC20 _lpToken,
    bool _withUpdate
  ) external onlyOwner {
    // when _pid is 0, it is Lab pool
    if (poolInfo.length == 0) {
      require(address(_lpToken) == address(Lab), "StakePool: invalid lp token");
    }

    if (_withUpdate) {
      massUpdatePools();
    }
    totalAllocPoint = totalAllocPoint + _allocPoint;
    poolInfo.push(
      PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: block.number,
        accPerShare: 0
      })
    );
  }

  // Update the given pool's prLab allocation point. Can only be called by the owner.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) external onlyOwner {
    if (_withUpdate) {
      massUpdatePools();
    }
    totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
    poolInfo[_pid].allocPoint = _allocPoint;
  }

  // Set options. Can only be called by the owner.
  function setOptions(
    uint32 _mintPercentPerDay,
    uint256 _blocksPerDay,
    address _dev,
    uint32 _withdrawFee,
    uint32 _mintFee,
    bool _withUpdate
  ) public onlyOwner {
    require(
      _mintPercentPerDay <= 10000,
      "StakePool: mintPercentPerDay is too large"
    );
    require(_blocksPerDay > 0, "StakePool: blocksPerDay is zero");
    require(_dev != address(0), "StakePool: zero dev address");
    require(_withdrawFee <= 10000, "StakePool: invalid withdrawFee");
    require(_mintFee <= 10000, "StakePool: invalid mintFee");
    if (_withUpdate) {
      massUpdatePools();
    }
    mintPercentPerDay = _mintPercentPerDay;
    blocksPerDay = _blocksPerDay;
    dev = _dev;
    withdrawFee = _withdrawFee;
    mintFee = _mintFee;
    emit OptionsChanged(
      _mintPercentPerDay,
      _blocksPerDay,
      _dev,
      _withdrawFee,
      _mintFee
    );
  }

  // View function to see pending prLabs on frontend.
  function pendingRewards(uint256 _pid, address _user)
    external
    view
    returns (uint256)
  {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accPerShare = pool.accPerShare;
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 pendingReward = (Lab.totalSupply() *
        1e12 *
        mintPercentPerDay *
        (block.number - pool.lastRewardBlock) *
        pool.allocPoint) / (10000 * blocksPerDay * totalAllocPoint);
      accPerShare += pendingReward / lpSupply;
    }
    return (user.amount * accPerShare) / 1e12 - user.rewardDebt;
  }

  // Update reward vairables for all pools. Be careful of gas spending!
  function massUpdatePools() public {
    uint256 totalSupply = Lab.totalSupply();
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid, totalSupply);
    }
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid, uint256 _totalSupply) internal {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.number <= pool.lastRewardBlock) {
      return;
    }
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (lpSupply == 0 || totalAllocPoint == 0) {
      pool.lastRewardBlock = block.number;
      return;
    }
    uint256 pendingReward = (_totalSupply *
      1e12 *
      mintPercentPerDay *
      (block.number - pool.lastRewardBlock) *
      pool.allocPoint) / (10000 * blocksPerDay * totalAllocPoint);
    uint256 mint = pendingReward / 1e12;
    prLab.mint(dev, (mint * mintFee) / 10000);
    prLab.mint(address(this), mint);
    pool.accPerShare += pendingReward / lpSupply;
    pool.lastRewardBlock = block.number;
  }

  // Deposit LP tokens to StakePool for prLab allocation.
  function deposit(uint256 _pid, uint256 _amount) external {
    depositFor(_pid, _amount, msg.sender);
  }

  // Deposit LP tokens to StakePool for user for prLab allocation.
  function depositFor(
    uint256 _pid,
    uint256 _amount,
    address _user
  ) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    updatePool(_pid, Lab.totalSupply());
    if (user.amount > 0) {
      uint256 pending = (user.amount * pool.accPerShare) /
        1e12 -
        user.rewardDebt;
      if (pending > 0) {
        safeTransfer(_user, pending);
      }
    }
    pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
    user.amount = user.amount + _amount;
    user.rewardDebt = (user.amount * pool.accPerShare) / 1e12;
    emit Deposit(_user, _pid, _amount);
  }

  // Withdraw LP tokens from StakePool.
  function withdraw(uint256 _pid, uint256 _amount) external {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, "StakePool: withdraw not good");
    updatePool(_pid, Lab.totalSupply());
    uint256 pending = (user.amount * pool.accPerShare) / 1e12 - user.rewardDebt;
    if (pending > 0) {
      safeTransfer(msg.sender, pending);
    }

    // when _pid is 0, it is Lab pool,
    // so we have to check the amount that can be withdrawn,
    // and calculate dev fee
    uint256 fee = 0;
    if (_pid == 0) {
      uint256 withdrawable = bank.withdrawable(msg.sender, user.amount);
      require(
        withdrawable >= _amount,
        "StakePool: amount exceeds withdrawable"
      );
      fee = (_amount * withdrawFee) / 10000;
    }

    user.amount = user.amount - _amount;
    user.rewardDebt = (user.amount * pool.accPerShare) / 1e12;
    pool.lpToken.safeTransfer(msg.sender, _amount - fee);
    pool.lpToken.safeTransfer(dev, fee);
    emit Withdraw(msg.sender, _pid, _amount - fee, fee);
  }

  // Claim reward.
  function claim(uint256 _pid) external {
    claimFor(_pid, msg.sender);
  }

  // Claim reward for user.
  function claimFor(uint256 _pid, address _user) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    require(user.amount > 0, "StakePool: claim not good");
    updatePool(_pid, Lab.totalSupply());
    uint256 pending = (user.amount * pool.accPerShare) / 1e12 - user.rewardDebt;
    if (pending > 0) {
      safeTransfer(_user, pending);
      user.rewardDebt = (user.amount * pool.accPerShare) / 1e12;
    }
  }

  // Safe prLab transfer function, just in case if rounding error causes pool to not have enough prLabs.
  function safeTransfer(address _to, uint256 _amount) internal {
    uint256 prLabBal = prLab.balanceOf(address(this));
    if (_amount > prLabBal) {
      prLab.transfer(_to, prLabBal);
    } else {
      prLab.transfer(_to, _amount);
    }
  }
}

