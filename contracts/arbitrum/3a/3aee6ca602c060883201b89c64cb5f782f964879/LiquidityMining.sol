// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IPool} from "./IPool.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";

interface ILiquidityMiningPlugin {
    function onHarvest(address from, address token, uint256 amount) external;
}

// Incentivize liquidity with token rewards, based on SushiSwap's MiniChef
contract LiquidityMining is Util {
    struct UserInfo {
        uint256 amount;
        uint256 lp;
        uint256 boostLp;
        uint256 boostLock;
        int256 rewardDebt;
        uint256 lock;
    }

    struct PoolInfo {
        uint256 totalAmount;
        uint128 accRewardPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    IStrategyHelper public strategyHelper;
    IERC20 public lpToken;
    IERC20 public rewardToken;
    uint256 public totalAllocPoint;
    uint256 public rewardPerDay;
    uint256 public boostMax = 1e18;
    uint256 public boostMaxDuration = 365 days;
    uint256 public lpBoostAmount = 1e18;
    uint256 public lpBoostThreshold = 0.05e18;
    uint256 public earlyWithdrawFeeMax = 0.75e18;
    bool public emergencyBypassLock = false;
    IERC20[] public token;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to, uint256 lock);
    event DepositLp(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event WithdrawLp(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event WithdrawEarly(address indexed user, uint256 indexed pid, uint256 amount, uint256 fee, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event FileInt(bytes32 what, uint256 data);
    event FileAddress(bytes32 what, address data);
    event PoolAdd(uint256 indexed pid, uint256 allocPoint, address indexed token);
    event PoolSet(uint256 indexed pid, uint256 allocPoint);
    event PoolUpdate(uint256 indexed pid, uint64 lastRewardBlock, uint256 lpSupply, uint256 accRewardPerShare);

    error BalanceTooLow();

    constructor() {
        exec[msg.sender] = true;
    }

    function file(bytes32 what, uint256 data) external auth {
        if (what == "paused") paused = data == 1;
        if (what == "rewardPerDay") rewardPerDay = data;
        if (what == "boostMax") boostMax = data;
        if (what == "boostMaxDuration") boostMaxDuration = data;
        if (what == "lpBoostAmount") lpBoostAmount = data;
        if (what == "lpBoostThreshold") lpBoostThreshold = data;
        if (what == "earlyWithdrawFeeMax") earlyWithdrawFeeMax = data;
        if (what == "emergencyBypassLock") emergencyBypassLock = data == 1;
        emit FileInt(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        if (what == "lpToken") lpToken = IERC20(data);
        if (what == "strategyHelper") strategyHelper = IStrategyHelper(data);
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
        _harvest(usr, pid, to, address(0));
        poolInfo[pid].totalAmount -= getBoostedAmount(info);
        uint256 amt = info.amount;
        uint256 amtLp = info.lp;
        info.amount = 0;
        info.lp = 0;
        info.boostLp = 0;
        info.boostLock = 0;
        info.rewardDebt = 0;
        info.lock = 0;
        token[pid].transfer(to, amt);
        lpToken.transfer(to, amtLp);
        emit Withdraw(usr, pid, amt, to);
        emit WithdrawLp(usr, pid, amtLp, to);
    }

    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    function pendingRewards(uint256 pid, address user) public view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[pid];
        UserInfo storage info = userInfo[pid][user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalAmount != 0) {
            uint256 timeSinceLastReward = block.timestamp - pool.lastRewardTime;
            uint256 reward = timeSinceLastReward * rewardPerDay * pool.allocPoint / totalAllocPoint / 86400;

            accRewardPerShare = accRewardPerShare + ((reward * 1e12) / pool.totalAmount);
        }
        pending = uint256(int256((getBoostedAmount(info) * accRewardPerShare) / 1e12) - info.rewardDebt);
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

    function _deposit(address usr, uint256 pid, uint256 amount, address to, uint256 lock) internal {
        PoolInfo memory pool = poolUpdate(pid);
        UserInfo storage info = userInfo[pid][to];
        _userUpdate(pid, info, lock, 0, int256(amount));
        emit Deposit(usr, pid, amount, to, lock);
    }

    function withdraw(uint256 pid, uint256 amount, address to) public loop live {
        _withdraw(msg.sender, pid, amount, to);
        token[pid].transfer(to, amount);
    }

    function withdrawWithUnwrap(uint256 pid, uint256 amount, address to) public loop live {
        _withdraw(msg.sender, pid, amount, to);
        IPool(address(token[pid])).burn(amount, to);
    }

    function _withdraw(address usr, uint256 pid, uint256 amount, address to) internal {
        PoolInfo memory pool = poolUpdate(pid);
        UserInfo storage info = userInfo[pid][usr];
        require(block.timestamp >= info.lock, "locked");
        _userUpdate(pid, info, 0, 0, 0 - int256(amount));
        emit Withdraw(msg.sender, pid, amount, to);
    }

    function withdrawEarly(uint256 pid, address to) public loop live {
        PoolInfo memory pool = poolUpdate(pid);
        UserInfo storage info = userInfo[pid][msg.sender];
        require(info.lock > 0, "no lock");
        require(block.timestamp < info.lock, "unlocked");
        // fee is % of max lock in time to unlock multiplied by feeMax multiplied by amount
        uint256 rate = earlyWithdrawFeeMax * (info.lock - block.timestamp) / boostMaxDuration;
        uint256 amount = info.amount;
        uint256 fee = amount * rate / 1e18;
        _userUpdate(pid, info, 0, 0, 0 - int256(amount));
        token[pid].transfer(to, amount - fee);
        token[pid].transfer(address(0), fee); // donate fee to reserve
        emit Withdraw(msg.sender, pid, amount - fee, to);
        emit WithdrawEarly(msg.sender, pid, amount - fee, fee, to);
    }

    function harvest(uint256 pid, address to, address plugin) public loop live {
        _harvest(msg.sender, pid, to, plugin);
    }

    function _harvest(address usr, uint256 pid, address to, address plugin) internal {
        PoolInfo memory pool = poolUpdate(pid);
        UserInfo storage info = userInfo[pid][usr];
        uint256 amount = getBoostedAmount(info);
        int256 total = int256(amount * pool.accRewardPerShare / 1e12);
        uint256 owed = uint256(total - info.rewardDebt);
        info.rewardDebt = total;
        if (owed != 0) {
            if (plugin != address(0)) {
                rewardToken.transfer(plugin, owed);
                ILiquidityMiningPlugin(plugin).onHarvest(to, address(rewardToken), owed);
            } else {
                rewardToken.transfer(to, owed);
            }
        }
        emit Harvest(usr, pid, owed);
    }

    function emergencyWithdraw(uint256 pid, address to) public loop live {
        UserInfo storage info = userInfo[pid][msg.sender];
        if (!emergencyBypassLock) require(block.timestamp >= info.lock, "locked");
        uint256 amount = info.amount;
        uint256 lpAmount = info.lp;
        _userUpdate(pid, info, 0, 0 - int256(lpAmount), 0 - int256(info.amount));
        info.rewardDebt = 0;
        if (amount > 0) token[pid].transfer(to, amount);
        if (lpAmount > 0) lpToken.transfer(to, lpAmount);
        emit Withdraw(msg.sender, pid, amount, to);
    }

    function depositLp(uint256 pid, address to, uint256 amount) public loop live {
        UserInfo storage info = userInfo[pid][to];
        lpToken.transferFrom(msg.sender, address(this), amount);
        _userUpdate(pid, info, 0, int256(amount), 0);
        emit DepositLp(msg.sender, pid, amount, to);
    }

    function withdrawLp(uint256 pid, uint256 amount, address to) public loop live {
        UserInfo storage info = userInfo[pid][msg.sender];
        _userUpdate(pid, info, 0, 0 - int256(amount), 0);
        lpToken.transfer(to, amount);
        emit WithdrawLp(msg.sender, pid, amount, to);
    }

    // Allow keeper / bot to update a user. So that when the value of their LP drops below 5%
    // but they are still earning as lp boosted they can be stopped
    function ping(uint256 pid, address user) external {
        UserInfo storage info = userInfo[pid][user];
        _userUpdate(pid, info, 0, 0, 0);
    }

    function _userUpdate(uint256 pid, UserInfo storage info, uint256 lock, int256 lp, int256 amount) internal {
        int256 prev = int256(getBoostedAmount(info));
        if (amount < 0 && uint256(0-amount) > info.amount) revert BalanceTooLow();
        if (amount != 0) info.amount = uint256(int256(info.amount) + amount);
        if (lock > 0) {
            require(info.lock == 0, "already locked");
            info.lock = block.timestamp + min(lock, boostMaxDuration);
            info.boostLock = boostMax * min(lock, boostMaxDuration) / boostMaxDuration;
        }
        if (info.lock > 0 && amount < 0) {
            info.lock = 0;
            info.boostLock = 0;
        }
        if (lp != 0) {
            IPool pool = IPool(address(token[pid]));
            uint256 value = strategyHelper.value(pool.asset(), info.amount * pool.getTotalLiquidity() / pool.totalSupply());
            if (lp < 0 && uint256(0-lp) > info.lp) revert BalanceTooLow();
            info.lp = uint256(int256(info.lp) + lp);
            uint256 lpValue = strategyHelper.value(address(lpToken), info.lp);
            if (lpValue > 0 && value > 0) {
                info.boostLp = (lpValue * 1e18 / value) > lpBoostThreshold ? lpBoostAmount : 0;
            } else if (info.boostLp > 0) {
                info.boostLp = 0;
            }
        }
        int256 next = int256(getBoostedAmount(info));
        info.rewardDebt += (next - prev) * int256(uint256(poolInfo[pid].accRewardPerShare)) / 1e12;
        poolInfo[pid].totalAmount = poolInfo[pid].totalAmount - uint256(prev) + uint256(next);
    }

    function getBoostedAmount(UserInfo storage info) internal view returns (uint256) {
        return info.amount * (1e18 + info.boostLock + info.boostLp) / 1e18;
    }

    function getUser(uint256 pid, address user)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        UserInfo memory info = userInfo[pid][user];
        IPool pool = IPool(address(token[pid]));
        uint256 value = strategyHelper.value(pool.asset(), info.amount * pool.getTotalLiquidity() / pool.totalSupply());
        uint256 lpValue = strategyHelper.value(address(lpToken), info.lp);
        uint256 owed = pendingRewards(pid, user);
        return (info.amount, info.lp, info.lock, info.boostLp, info.boostLock, owed, value, lpValue);
    }
}

