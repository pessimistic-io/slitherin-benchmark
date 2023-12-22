// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./Math.sol";
import "./IERC20.sol";

// MasterChef is the master of Cake. He can make Cake and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once CAKE is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract LPMasterChef is Ownable {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        address stakeToken;
        address rewardToken;
        uint256 lastRewardTimestamp;
        uint256 rewardPerSecond;
        uint256 rewardPerShare; //multiply 1e20
    }

    mapping(uint256 => uint256) public totalStake;
    IStrictERC20 public vin;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(address _vin, uint256 startTimestamp) {
        vin = IStrictERC20(_vin);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addPool(uint256 _rewardPerSecond, address _stakeToken, uint256 startTimestamp, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        poolInfo.push(
            PoolInfo({
                stakeToken: _stakeToken,
                rewardToken: address(vin),
                lastRewardTimestamp: startTimestamp,
                rewardPerSecond: _rewardPerSecond,
                rewardPerShare: 0
            })
        );
    }

    function updateRewardPerBlock(uint256 _rewardPerSecond, uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        require(_pid > 2, "can not update reward");
        updatePool(_pid);
        pool.rewardPerSecond = _rewardPerSecond;
    }

    function withdrawReward(address token, uint256 amount) external onlyOwner {
        IStrictERC20(token).transfer(msg.sender, amount);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending CAKEs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        uint256 lpSupply = totalStake[_pid];
        if (lpSupply == 0) {
            return 0;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTimestamp, block.timestamp);
        uint256 reward = multiplier.mul(pool.rewardPerSecond);
        rewardPerShare = rewardPerShare.add(reward.mul(1e20).div(lpSupply));
        return user.amount.mul(rewardPerShare).div(1e20).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = totalStake[_pid];
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTimestamp, block.timestamp);
        uint256 reward = multiplier.mul(pool.rewardPerSecond);
        pool.rewardPerShare = pool.rewardPerShare.add(reward.mul(1e20).div(lpSupply));
        pool.lastRewardTimestamp = block.timestamp;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        updatePool(_pid);
        address to = msg.sender;
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][to];
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
            if (pending > 0) {
                IStrictERC20(pool.rewardToken).transfer(to, pending);
            }
        }
        if (_amount > 0) {
            IStrictERC20(pool.stakeToken).transferFrom(address(to), address(this), _amount);
            user.amount = user.amount.add(_amount);
            totalStake[_pid] += _amount;
            emit Deposit(msg.sender, _pid, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e20);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        updatePool(_pid);
        address to = msg.sender;
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][to];
        require(user.amount >= _amount, "withdraw: not good");
        uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
        if (pending > 0) {
            IStrictERC20(pool.rewardToken).transfer(to, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            totalStake[_pid] -= _amount;
            IStrictERC20(pool.stakeToken).transfer(to, _amount);
            emit Withdraw(to, _pid, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e20);
    }

    function claimPending(uint256 _pid) public {
        updatePool(_pid);
        PoolInfo memory pool = poolInfo[_pid];
        address to = msg.sender;
        UserInfo storage user = userInfo[_pid][to];
        uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e20).sub(user.rewardDebt);
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e20);
        if (pending > 0) {
            IStrictERC20(pool.rewardToken).transfer(to, pending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        address operator = msg.sender;
        UserInfo storage user = userInfo[_pid][operator];
        totalStake[_pid] -= user.amount;
        emit EmergencyWithdraw(operator, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        IStrictERC20(pool.stakeToken).transfer(operator, user.amount);
    }
}

