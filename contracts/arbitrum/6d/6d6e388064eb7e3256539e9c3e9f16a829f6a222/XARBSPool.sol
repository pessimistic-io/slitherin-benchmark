// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";

interface IERC20Ext is IERC20 {
    function decimals() external returns (uint256);
}

// The goal of this farm is to allow a stake XArbs earn anything model
// In a flip of a traditional farm, this contract only accepts XArbs as the staking token
// Each new pool added is a new reward token, each with its own start times
// end times, and rewards per second.
contract XARBSPool is Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 RewardToken; // Address of reward token contract.
        uint256 RewardPerSecond; // reward token per second for this pool
        uint256 TokenPrecision; // The precision factor used for calculations, dependent on a tokens decimals
        uint256 XArbsStakedAmount; // # of XArbs allocated to this pool
        uint256 lastRewardTime; // Last block time that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward per share, times the pools token precision. See below.
        uint256 endTime; // end time of pool
        uint256 startTime; // start time of pool
        uint256 userLimitEndTime;
        address protocolOwnerAddress; // this address is the owner of the protocol corresponding to the reward token, used for emergency withdraw to them only
    }

    IERC20 public immutable XArbs;
    uint256 public baseUserLimitTime = 2 days;
    uint256 public baseUserLimit = 0;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Record whether reward was added.
    mapping(address => bool) public rewardTokenAdded;
    // Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetRewardPerSecond(uint256 _pid, uint256 _gemsPerSecond);

    constructor(IERC20 _XArbs) {
        XArbs = _XArbs;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to,
        PoolInfo memory pool
    ) internal pure returns (uint256) {
        _from = _from > pool.startTime ? _from : pool.startTime;
        if (_from > pool.endTime || _to < pool.startTime) {
            return 0;
        }
        if (_to > pool.endTime) {
            return pool.endTime - _from;
        }
        return _to - _from;
    }

    // View function to see pending XArbs on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        if (block.timestamp > pool.lastRewardTime && pool.XArbsStakedAmount != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp, pool);
            uint256 reward = multiplier * pool.RewardPerSecond;
            accRewardPerShare += (reward * pool.TokenPrecision) / pool.XArbsStakedAmount;
        }
        return ((user.amount * accRewardPerShare) / pool.TokenPrecision) - user.rewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        if (pool.XArbsStakedAmount == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp, pool);
        uint256 reward = multiplier * pool.RewardPerSecond;

        pool.accRewardPerShare += (reward * pool.TokenPrecision) / pool.XArbsStakedAmount;
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit tokens.
    function deposit(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (baseUserLimit > 0 && block.timestamp < pool.userLimitEndTime) {
            require(user.amount + _amount <= baseUserLimit, "deposit: user has hit deposit cap");
        }

        updatePool(_pid);

        uint256 pending = ((user.amount * pool.accRewardPerShare) / pool.TokenPrecision) - user.rewardDebt;

        user.amount += _amount;
        pool.XArbsStakedAmount += _amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / pool.TokenPrecision;

        if (pending > 0) {
            safeTransfer(pool.RewardToken, msg.sender, pending);
        }
        XArbs.safeTransferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw tokens.
    function withdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        uint256 pending = ((user.amount * pool.accRewardPerShare) / pool.TokenPrecision) - user.rewardDebt;

        user.amount -= _amount;
        pool.XArbsStakedAmount -= _amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / pool.TokenPrecision;

        if (pending > 0) {
            safeTransfer(pool.RewardToken, msg.sender, pending);
        }

        safeTransfer(XArbs, address(msg.sender), _amount);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 oldUserAmount = user.amount;
        pool.XArbsStakedAmount -= user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        XArbs.safeTransfer(address(msg.sender), oldUserAmount);
        emit EmergencyWithdraw(msg.sender, _pid, oldUserAmount);
    }

    // Safe erc20 transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function safeTransfer(
        IERC20 token,
        address _to,
        uint256 _amount
    ) internal {
        uint256 bal = token.balanceOf(address(this));
        if (_amount > bal) {
            token.safeTransfer(_to, bal);
        } else {
            token.safeTransfer(_to, _amount);
        }
    }

    // Admin functions

    function changeEndTime(uint256 _pid, uint32 addSeconds) external onlyOwner {
        poolInfo[_pid].endTime += addSeconds;
    }

    function stopReward(uint256 _pid) external onlyOwner {
        poolInfo[_pid].endTime = block.number;
    }

    function changePoolUserLimitEndTime(uint256 _pid, uint256 _time) external onlyOwner {
        poolInfo[_pid].userLimitEndTime = _time;
    }

    function changeUserLimit(uint256 _limit) external onlyOwner {
        baseUserLimit = _limit;
    }

    function changeBaseUserLimitTime(uint256 _time) external onlyOwner {
        baseUserLimitTime = _time;
    }

    function recoverWrongTokens(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(XArbs), "Cannot be XArbs!");
        require(!rewardTokenAdded[_tokenAddress], "Can not be reward token!");

        uint256 bal = IERC20(_tokenAddress).balanceOf(address(this));
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), bal);

        emit AdminTokenRecovery(_tokenAddress, bal);
    }

    function emergencyRewardWithdraw(uint256 _pid, uint256 _amount) external onlyOwner {
        poolInfo[_pid].RewardToken.safeTransfer(poolInfo[_pid].protocolOwnerAddress, _amount);
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _rewardPerSecond,
        IERC20Ext _Token,
        uint256 _startTime,
        uint256 _endTime,
        address _protocolOwner
    ) external onlyOwner {
        rewardTokenAdded[address(_Token)] = true;

        uint256 lastRewardTime = block.timestamp > _startTime ? block.timestamp : _startTime;
        uint256 decimalsRewardToken = _Token.decimals();
        require(decimalsRewardToken < 30, "Token has way too many decimals");
        uint256 precision = 10**(30 - decimalsRewardToken);

        poolInfo.push(
            PoolInfo({
                RewardToken: _Token,
                RewardPerSecond: _rewardPerSecond,
                TokenPrecision: precision,
                XArbsStakedAmount: 0,
                startTime: _startTime,
                endTime: _endTime,
                lastRewardTime: lastRewardTime,
                accRewardPerShare: 0,
                protocolOwnerAddress: _protocolOwner,
                userLimitEndTime: lastRewardTime + baseUserLimitTime
            })
        );
    }

    // Update the given pool's reward per second. Can only be called by the owner.
    function setRewardPerSecond(uint256 _pid, uint256 _rewardPerSecond) external onlyOwner {
        updatePool(_pid);

        poolInfo[_pid].RewardPerSecond = _rewardPerSecond;

        emit SetRewardPerSecond(_pid, _rewardPerSecond);
    }
}

