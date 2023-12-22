// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";

contract MasterChef is Ownable, ReentrancyGuard {
  using SafeMath for uint256;

  IERC20 public immutable PLS;
  uint256 public constant MONTH_IN_SECONDS = 2_628_000 seconds;

  // Info of each user.
  struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
    //
    // We do some fancy math here. Basically, any point in time, the amount of PLS
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (user.amount * pool.accPlsPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    //   1. The pool's `accPlsPerShare` (and `lastRewardSecond`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `amount` gets updated.
    //   4. User's `rewardDebt` gets updated.
  }

  // Info of each pool.
  struct PoolInfo {
    IERC20 lpToken; // Address of LP token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. PLS to emit per second
    uint256 lastRewardSecond; // Last block timestamp that PLS distribution occurs.
    uint256 accPlsPerShare; // Accumulated PLS per share, times 1e18. See below.
    uint256 lpSupply;
  }

  // PLS tokens emitted per second.
  uint256 public plsPerSecond;

  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes LP tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  // Total allocation points. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint = 0;

  // The block timestamp where PLS mining starts
  // poolId => timestamp;
  mapping(uint256 => uint256) startTime;

  constructor(
    address _pls,
    address _gov,
    uint256 _initialEmission
  ) {
    PLS = IERC20(_pls);
    transferOwnership(_gov);
    plsPerSecond = _initialEmission / MONTH_IN_SECONDS;
  }

  // Deposit LP tokens to MasterChef for PLS allocation.
  function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    if (user.amount > 0) {
      uint256 pending = user.amount.mul(pool.accPlsPerShare).div(1e18).sub(user.rewardDebt);
      if (pending > 0) {
        safePlsTransfer(msg.sender, pending);
      }
    }
    if (_amount > 0) {
      uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
      pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
      _amount = pool.lpToken.balanceOf(address(this)) - balanceBefore;

      user.amount = user.amount.add(_amount);
      pool.lpSupply = pool.lpSupply.add(_amount);
    }
    user.rewardDebt = user.amount.mul(pool.accPlsPerShare).div(1e18);
    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw LP tokens from MasterChef.
  function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, 'withdraw: not good');
    updatePool(_pid);
    uint256 pending = user.amount.mul(pool.accPlsPerShare).div(1e18).sub(user.rewardDebt);
    if (pending > 0) {
      safePlsTransfer(msg.sender, pending);
    }
    if (_amount > 0) {
      user.amount = user.amount.sub(_amount);
      pool.lpToken.transfer(address(msg.sender), _amount);
      pool.lpSupply = pool.lpSupply.sub(_amount);
    }
    user.rewardDebt = user.amount.mul(pool.accPlsPerShare).div(1e18);
    emit Withdraw(msg.sender, _pid, _amount);
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    uint256 amount = user.amount;
    user.amount = 0;
    user.rewardDebt = 0;
    pool.lpToken.transfer(address(msg.sender), amount);

    if (pool.lpSupply >= amount) {
      pool.lpSupply = pool.lpSupply.sub(amount);
    } else {
      pool.lpSupply = 0;
    }

    emit EmergencyWithdraw(msg.sender, _pid, amount);
  }

  // Safe pls transfer function, just in case if rounding error causes pool to not have enough PLS.
  function safePlsTransfer(address _to, uint256 _amount) internal {
    uint256 plsBal = PLS.balanceOf(address(this));
    bool transferSuccess = false;
    if (_amount > plsBal) {
      transferSuccess = PLS.transfer(_to, plsBal);
    } else {
      transferSuccess = PLS.transfer(_to, _amount);
    }
    require(transferSuccess, 'safePlsTransfer: transfer failed');
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  // Return reward multiplier over the given _from to _to second.
  function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
    return _to.sub(_from);
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];

    if (block.timestamp <= pool.lastRewardSecond) {
      return;
    }

    if (pool.lpSupply == 0 || pool.allocPoint == 0) {
      pool.lastRewardSecond = block.timestamp;
      return;
    }

    uint256 multiplier = getMultiplier(pool.lastRewardSecond, block.timestamp);
    uint256 plsReward = multiplier.mul(plsPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
    pool.accPlsPerShare = pool.accPlsPerShare.add(plsReward.mul(1e18).div(pool.lpSupply));
    pool.lastRewardSecond = block.timestamp;
  }

  // Update reward variables for all pools. Be careful of gas spending!
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid);
    }
  }

  // View function to see pending pls on frontend.
  function pendingPls(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accPlsPerShare = pool.accPlsPerShare;
    if (block.timestamp > pool.lastRewardSecond && pool.lpSupply != 0 && totalAllocPoint > 0) {
      uint256 multiplier = getMultiplier(pool.lastRewardSecond, block.timestamp);
      uint256 plsReward = multiplier.mul(plsPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
      accPlsPerShare = accPlsPerShare.add(plsReward.mul(1e18).div(pool.lpSupply));
    }
    return user.amount.mul(accPlsPerShare).div(1e18).sub(user.rewardDebt);
  }

  /** OWNER ONLY */
  function updateEmissionRate(uint256 _plsPerSecond) external onlyOwner {
    massUpdatePools();
    plsPerSecond = _plsPerSecond;
    emit UpdateEmissionRate(msg.sender, _plsPerSecond);
  }

  // Add a new lp to the pool. Can only be called by the owner.
  function add(
    uint256 _allocPoint,
    IERC20 _lpToken,
    bool _withUpdate
  ) external onlyOwner {
    if (_withUpdate) {
      massUpdatePools();
    }

    uint256 lastRewardSecond = block.timestamp;
    startTime[poolInfo.length] = lastRewardSecond;

    totalAllocPoint = totalAllocPoint.add(_allocPoint);

    poolInfo.push(
      PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardSecond: lastRewardSecond,
        accPlsPerShare: 0,
        lpSupply: 0
      })
    );
  }

  // Update the given pool's PLS allocation point. Can only be called by the owner.
  function set(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) external onlyOwner {
    if (_withUpdate) {
      massUpdatePools();
    }

    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
    poolInfo[_pid].allocPoint = _allocPoint;
  }

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event UpdateEmissionRate(address indexed caller, uint256 newAmount);
}

