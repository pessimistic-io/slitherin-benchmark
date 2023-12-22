// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

// Note that this pool has no minter key of gSHARE (rewards).
// Instead, the governance will call gSHARE distributeReward method and send reward to this pool at the beginning.
contract GShareRewardPool is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 depFee; // deposit fee that is applied to created pool.
        uint256 allocPoint; // How many allocation points assigned to this pool. gSHAREs to distribute per block.
        uint256 lastRewardTime; // Last time that gSHAREs distribution occurs.
        uint256 accGSharePerShare; // Accumulated gSHAREs per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
    }

    IERC20 public gshare;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when gSHARE mining starts.
    uint256 public poolStartTime;

    // The time when gSHARE mining ends.
    uint256 public poolEndTime;

    address public daoFundAddress;

    uint256 public gSharePerSecond = 0.003486 ether; // 50000 gshare / (166 days * 24h * 60min * 60s)
    uint256 public runningTime = 166 days; // 166 days
    uint256 public constant TOTAL_REWARDS = 50000 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(address _gshare, address _daoFund, uint256 _poolStartTime) {
        require(block.timestamp < _poolStartTime, "pool cant be started in the past");
        if (_gshare != address(0)) gshare = IERC20(_gshare);
        if (_daoFund != address(0)) daoFundAddress = _daoFund;

        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "GShareRewardPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "GShareRewardPool: existing pool?");
        }
    }

    // Add new lp to the pool. Can only be called by operator.
    function add(uint256 _allocPoint, uint256 _depFee, IERC20 _token, bool _withUpdate, uint256 _lastRewardTime)
        public
        onlyOperator
    {
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted = (_lastRewardTime <= poolStartTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(
            PoolInfo({
                token: _token,
                depFee: _depFee,
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                accGSharePerShare: 0,
                isStarted: _isStarted
            })
        );
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's gSHARE allocation point. Can only be called by the operator.
    // @allocPoints for TEAM can NOT be altered after added - PID 2
    // @allocPoints for main LP pools can NOT be smaller than 12,000
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depFee) public onlyOperator {
        massUpdatePools();
        require(_pid != 2, "CAN NOT ADJUST TEAM ALLOCATIONS");

        PoolInfo storage pool = poolInfo[_pid];

        if (_pid == 0 || _pid == 1) {
            require(_allocPoint >= 12000 * 10 ** 18, "out of range"); // >= allocations for lp pools cant be less than 12,000
            if (pool.isStarted) {
                totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
            }
        } else if (_pid > 2) {
            require(_allocPoint < 12000 * 10 ** 18, "cant be more then native lps");
            require(_depFee < 200); // deposit fee cant be more than 2%;
            pool.depFee = _depFee;

            if (pool.isStarted) {
                totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
            }
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(gSharePerSecond);
            return poolEndTime.sub(_fromTime).mul(gSharePerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(gSharePerSecond);
            return _toTime.sub(_fromTime).mul(gSharePerSecond);
        }
    }

    // View function to see pending gSHAREs on frontend.
    function pendingShare(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accGSharePerShare = pool.accGSharePerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _gshareReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accGSharePerShare = accGSharePerShare.add(_gshareReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accGSharePerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) private {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _gshareReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accGSharePerShare = pool.accGSharePerShare.add(_gshareReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accGSharePerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeGShareTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            uint256 depositDebt = _amount.mul(pool.depFee).div(10000);
            user.amount = user.amount.add(_amount.sub(depositDebt));
            pool.token.safeTransfer(daoFundAddress, depositDebt);
        }
        user.rewardDebt = user.amount.mul(pool.accGSharePerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accGSharePerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeGShareTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accGSharePerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe gshare transfer function, just in case if rounding error causes pool to not have enough gSHAREs.
    function safeGShareTransfer(address _to, uint256 _amount) internal {
        uint256 _gshareBal = gshare.balanceOf(address(this));
        if (_gshareBal > 0) {
            if (_amount > _gshareBal) {
                gshare.safeTransfer(_to, _gshareBal);
            } else {
                gshare.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function recoverGShare(address _to, uint256 _amount) external onlyOperator {
        gshare.safeTransfer(_to, _amount);
    }
}

