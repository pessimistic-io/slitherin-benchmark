// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IPool} from "./IPool.sol";
import {IERC20} from "./IERC20.sol";

// Incentivize liquidity with token rewards, based on SushiSwap's MiniChef
contract LiquidityMining is Util {
    struct UserInfo {
        uint256 amount;
        uint256 boost;
        int256 rewardDebt;
        uint256 lock;
    }

    struct PoolInfo {
        uint256 totalAmount;
        uint128 accRewardPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    IERC20 public rewardToken;
    uint256 public rewardPerDay;
    uint256 public totalAllocPoint;
    uint256 public boostMax = 1e18;
    uint256 public boostMaxDuration = 365 days;
    bool public emergencyBypassLock = true;
    IERC20[] public token;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to, uint256 lock);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event FileInt(bytes32 what, uint256 data);
    event FileAddress(bytes32 what, address data);
    event PoolAdd(uint256 indexed pid, uint256 allocPoint, address indexed token);
    event PoolSet(uint256 indexed pid, uint256 allocPoint);
    event PoolUpdate(uint256 indexed pid, uint64 lastRewardBlock, uint256 lpSupply, uint256 accRewardPerShare);

    constructor() {
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "paused") paused = data == 1;
        if (what == "rewardPerDay") rewardPerDay = data;
        if (what == "boostMax") boostMax = data;
        if (what == "boostMaxDuration") boostMaxDuration = data;
        if (what == "emergencyBypassLock") emergencyBypassLock = data == 1;
        emit FileInt(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "rewardToken") rewardToken = IERC20(data);
        emit FileAddress(what, data);
    }

    function poolAdd(uint256 allocPoint, address _token) public auth {
        totalAllocPoint = totalAllocPoint + allocPoint;
        token.push(IERC20(_token));

        poolInfo.push(
            PoolInfo({
                totalAmount: 0,
                accRewardPerShare: 0,
                lastRewardTime: uint64(block.timestamp),
                allocPoint: uint64(allocPoint)
            })
        );
        emit PoolAdd(token.length - 1, allocPoint, _token);
    }

    function poolSet(uint256 _pid, uint256 _allocPoint) public auth {
        totalAllocPoint = (totalAllocPoint - poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = uint64(_allocPoint);
        emit PoolSet(_pid, _allocPoint);
    }

    function removeUser(uint256 pid, address usr, address to) public auth {
        UserInfo storage info = userInfo[pid][usr];
        _harvest(usr, pid, to);
        uint256 amt = info.amount;
        token[pid].transfer(to, amt);
        info.amount = 0;
        info.rewardDebt = 0;
        info.lock = 0;
        info.boost = 0;
        emit Withdraw(usr, pid, amt, to);
    }

    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    function pendingRewards(uint256 _pid, address _user) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalAmount != 0) {
            uint256 timeSinceLastReward = block.timestamp - pool.lastRewardTime;
            uint256 reward = timeSinceLastReward * rewardPerDay * pool.allocPoint / totalAllocPoint / 86400;

            accRewardPerShare = accRewardPerShare + ((reward * 1e12) / pool.totalAmount);
        }
        uint256 boostedAmount = user.amount * (1e18 + user.boost) / 1e18;
        pending = uint256(int256((boostedAmount * accRewardPerShare) / 1e12) - user.rewardDebt);
    }

    function poolUpdateMulti(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            poolUpdate(pids[i]);
        }
    }

    function poolUpdate(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            if (pool.totalAmount > 0) {
                uint256 timeSinceLastReward = block.timestamp - pool.lastRewardTime;
                uint256 reward = timeSinceLastReward * rewardPerDay * pool.allocPoint / totalAllocPoint / 86400;
                pool.accRewardPerShare = pool.accRewardPerShare + uint128((reward * 1e12) / pool.totalAmount);
            }
            pool.lastRewardTime = uint64(block.timestamp);
            poolInfo[pid] = pool;
            emit PoolUpdate(pid, pool.lastRewardTime, pool.totalAmount, pool.accRewardPerShare);
        }
    }

    function deposit(uint256 pid, uint256 amount, address to, uint256 lock) public loop live {
        token[pid].transferFrom(msg.sender, address(this), amount);
        _deposit(msg.sender, pid, amount, to, lock);
    }

    function depositAndWrap(uint256 pid, uint256 amount, address to, uint256 lock) public loop live {
        IPool pool = IPool(address(token[pid]));
        uint256 bef = IERC20(address(pool)).balanceOf(address(this));
        IERC20 tok = IERC20(pool.asset());
        tok.transferFrom(msg.sender, address(this), amount);
        tok.approve(address(pool), amount);
        pool.mint(amount, address(this));
        uint256 aft = IERC20(address(pool)).balanceOf(address(this));
        _deposit(msg.sender, pid, aft - bef, to, lock);
    }

    function _deposit(address usr, uint256 pid, uint256 amount, address to, uint256 lock) internal {
        PoolInfo memory pool = poolUpdate(pid);
        UserInfo storage user = userInfo[pid][to];
        if (lock > 0) {
            require(user.lock == 0, "already locked");
            require(user.amount == 0, "lock when already deposited");
            user.lock = block.timestamp + min(lock, boostMaxDuration);
            user.boost = boostMax * min(lock, boostMaxDuration) / boostMaxDuration;
        }
        if (user.lock > 0 && block.timestamp >= user.lock) {
            revert("widthdaw everything before depositing more");
        }
        user.amount = user.amount + amount;
        uint256 boostedAmount = amount * (1e18 + user.boost) / 1e18;
        user.rewardDebt = user.rewardDebt + int256((boostedAmount * pool.accRewardPerShare) / 1e12);
        poolInfo[pid].totalAmount += boostedAmount;
        emit Deposit(usr, pid, amount, to, lock);
    }

    function withdraw(uint256 pid, uint256 amount, address to) public loop live {
        _withdraw(msg.sender, pid, amount, to);
        token[pid].transfer(to, amount);
    }

    function withdrawAndUnwrap(uint256 pid, uint256 amount, address to) public loop live {
        _withdraw(msg.sender, pid, amount, to);
        IPool(address(token[pid])).burn(amount, to);
    }

    function _withdraw(address usr, uint256 pid, uint256 amount, address to) internal {
        PoolInfo memory pool = poolUpdate(pid);
        UserInfo storage info = userInfo[pid][usr];
        require(block.timestamp >= info.lock, "locked");
        uint256 boostedAmount = amount * (1e18 + info.boost) / 1e18;
        info.rewardDebt = info.rewardDebt - int256((boostedAmount * pool.accRewardPerShare) / 1e12);
        info.amount = info.amount - amount;
        poolInfo[pid].totalAmount -= boostedAmount;
        if (info.amount == 0) {
            info.lock = 0;
            info.boost = 0;
        }
        emit Withdraw(msg.sender, pid, amount, to);
    }

    function harvest(uint256 pid, address to) public loop live {
        _harvest(msg.sender, pid, to);
    }

    function _harvest(address usr, uint256 pid, address to) internal {
        PoolInfo memory pool = poolUpdate(pid);
        UserInfo storage info = userInfo[pid][usr];
        uint256 boostedAmount = info.amount * (1e18 + info.boost) / 1e18;
        int256 accumulatedReward = int256((boostedAmount * pool.accRewardPerShare) / 1e12);
        uint256 _pendingReward = uint256(accumulatedReward - info.rewardDebt);
        info.rewardDebt = accumulatedReward;
        if (_pendingReward != 0) {
            rewardToken.transfer(to, _pendingReward);
        }
        emit Harvest(usr, pid, _pendingReward);
    }

    function emergencyWithdraw(uint256 pid, address to) public loop live {
        UserInfo storage user = userInfo[pid][msg.sender];
        if (!emergencyBypassLock) require(block.timestamp >= user.lock, "locked");
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.lock = 0;
        user.boost = 0;
        token[pid].transfer(to, amount);
        emit Withdraw(msg.sender, pid, amount, to);
    }
}

