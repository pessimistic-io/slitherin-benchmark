// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

// Note that this pool has no minter key of MANGO (rewards).
// Instead, the governance will call MANGO distributeReward method and send reward to this pool at the beginning.
contract MangoGenesisRewardPool is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public operator;

    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. MANGO to distribute.
        uint256 lastRewardTime; // Last time that MANGO distribution occurs.
        uint256 accMangoPerShare; // Accumulated MANGO per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
        uint256 depositFee; // Deposit fee for staking in the pools.
    }

    IERC20 public mango;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when MANGO mining starts.
    uint256 public poolStartTime;

    // The time when MANGO mining ends.
    uint256 public poolEndTime;

    // MAINNET
    uint256 public runningTime = 1 days; // 1 days
    uint256 public constant TOTAL_REWARDS = 1800 ether;
    // END MAINNET

    uint256 public mangoPerSecond;

    // Fee allocation variables.
    uint256 public constant MAX_DEPOSIT_FEE = 150;

    address public feeWallet;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event DepositTaxPaid(address indexed user, uint256 amount);

    constructor(
        address _mango,
        uint256 _poolStartTime
    ) public {
        require(block.timestamp < _poolStartTime, "late");
        if (_mango != address(0)) mango = IERC20(_mango);
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
        feeWallet = msg.sender;
        mangoPerSecond = TOTAL_REWARDS.div(runningTime);
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "MangoGenesisPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "MangoGenesisPool: existing pool?");
        }
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime,
        uint256 _depositFee
    ) public onlyOperator {
        require(_depositFee <= MAX_DEPOSIT_FEE, "Error: Deposit fee too high.");
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
        bool _isStarted =
        (_lastRewardTime <= poolStartTime) ||
        (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
            token : _token,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accMangoPerShare : 0,
            isStarted : _isStarted,
            depositFee: _depositFee
        }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's MANGO allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFee) public onlyOperator {
        require(_depositFee <= MAX_DEPOSIT_FEE, "Error: Deposit fee too high.");
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
        pool.depositFee = _depositFee;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(mangoPerSecond);
            return poolEndTime.sub(_fromTime).mul(mangoPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(mangoPerSecond);
            return _toTime.sub(_fromTime).mul(mangoPerSecond);
        }
    }

    // View function to see pending MANGO on frontend.
    function pendingMANGO(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMangoPerShare = pool.accMangoPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _mangoReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accMangoPerShare = accMangoPerShare.add(_mangoReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accMangoPerShare).div(1e18).sub(user.rewardDebt);
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
            uint256 _mangoReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accMangoPerShare = pool.accMangoPerShare.add(_mangoReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public {
        address _sender = msg.sender;
        require(_sender!= _referrer, "referrer can't be yourself");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accMangoPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeMangoTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            // Deposit amount that accounts for transfer tax on taxable tokens.
            uint256 tokenBalanceBefore = pool.token.balanceOf(address(this));
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            _amount = pool.token.balanceOf(address(this)).sub(tokenBalanceBefore);
            // Calculate and distribute fees.
            uint256 feeAmount = _amount.mul(pool.depositFee).div(10000);
            _amount = _amount.sub(feeAmount);
            uint256 referrerFee = feeAmount/10;
            pool.token.safeTransfer(_referrer, referrerFee);
            feeAmount = feeAmount - referrerFee;
            pool.token.safeTransfer(feeWallet, feeAmount);
            emit DepositTaxPaid(_sender, feeAmount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMangoPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accMangoPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeMangoTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        // Update withdraw variables before token transfer to prevent re-entrancy.
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accMangoPerShare).div(1e18);
        if (_amount > 0) {
            pool.token.safeTransfer(_sender, _amount);
        }
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

    // Safe MANGO transfer function, just in case if rounding error causes pool to not have enough MANGOs.
    function safeMangoTransfer(address _to, uint256 _amount) internal {
        uint256 _mangoBalance = mango.balanceOf(address(this));
        if (_mangoBalance > 0) {
            if (_amount > _mangoBalance) {
                mango.safeTransfer(_to, _mangoBalance);
            } else {
                mango.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }
}
