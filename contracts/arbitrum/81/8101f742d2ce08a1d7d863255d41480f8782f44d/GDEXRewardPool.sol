// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./Initializable.sol";

contract GDEXRewardPool is Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 token;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accRewardSharePerShare;
        bool isStarted;
    }

    IERC20 public rewardToken;
    address public operator;
    uint256 public totalAllocPoint = 0;
    uint256 public poolStartTime;
    uint256 public poolEndTime;
    uint256 public sharesPerSecond;
    uint256 public totalPendingShare;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    uint256 public nextDepositFundsTime;
    uint256 public depositFundsInterval;

    function pendingShare(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardSharePerShare = pool.accRewardSharePerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _reward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accRewardSharePerShare = accRewardSharePerShare.add(_reward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accRewardSharePerShare).div(1e18).sub(user.rewardDebt);
    }

    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(sharesPerSecond);
            return poolEndTime.sub(_fromTime).mul(sharesPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(sharesPerSecond);
            return _toTime.sub(_fromTime).mul(sharesPerSecond);
        }
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event DepositedFunds(address indexed sender, uint256 amount, uint256 sharesPerSecond);

    constructor(
        address _rewardToken,
        uint256 _depositFundsInterval
    ) {
        require(_rewardToken != address(0), "GDEXRewardPool: RewardToken is zero address");
        rewardToken = IERC20(_rewardToken);
        depositFundsInterval = _depositFundsInterval;
        operator = msg.sender;
    }

    function initialize(uint256 _poolStartTime, uint256 _poolEndTime) external initializer returns (bool) {
        require(_poolStartTime > block.timestamp, "GDEXRewardPool: Start time lte current timestamp");
        require(_poolEndTime > _poolStartTime, "GDEXRewardPool: End time lte start time");
        poolStartTime = _poolStartTime;
        poolEndTime = _poolEndTime;
        nextDepositFundsTime = _poolStartTime;

        return true;
    }

    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) external onlyOperator {
        checkPoolDuplicate(_token);
        if (_withUpdate) massUpdatePools();
        if (block.timestamp < poolStartTime) {
            if (_lastRewardTime == 0) _lastRewardTime = poolStartTime;
            else if (_lastRewardTime < poolStartTime) _lastRewardTime = poolStartTime;
        } else {
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) _lastRewardTime = block.timestamp;
        }
        bool _isStarted = (_lastRewardTime <= poolStartTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
            token : _token,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accRewardSharePerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) totalAllocPoint = totalAllocPoint.add(_allocPoint);
    }

    function deposit(uint256 _pid, uint256 _amount) external {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accRewardSharePerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                totalPendingShare = totalPendingShare.sub(_pending);
                safeRewardTokenShareTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardSharePerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        massUpdatePools();
        uint256 poolLength = poolInfo.length;
        if (block.timestamp < poolEndTime + 5 days) {
            require(_token != rewardToken, "GDEXRewardPool: Recover token eq RewardToken");
            for (uint256 pid = 0; pid < poolLength; pid++) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "GDEXRewardPool: Recover token eq pool token");
            }
        } else if (_token == rewardToken) {
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            require(rewardBalance > totalPendingShare, "GDEXRewardPool: No reward tokens to recover");
            require(
                amount <= rewardBalance.sub(totalPendingShare),
                "GDEXRewardPool: Amount gt possible to recover"
            );
        }
        _token.safeTransfer(to, amount);
    }

    function set(uint256 _pid, uint256 _allocPoint) external onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        pool.allocPoint = _allocPoint;
    }

    function setOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "GDEXRewardPool: Operator is zero address");
        operator = _operator;
    }

    function setDepositFundsInterval(uint256 _depositFundsInterval) external onlyOperator {
        depositFundsInterval = _depositFundsInterval;
    }

    function setSharesPerSecond(uint256 _sharesPerSecond) external onlyOperator {
        sharesPerSecond = _sharesPerSecond;
    }

    function setPoolEndTime(uint256 _poolEndTime) external onlyOperator {
        require(
            _poolEndTime >= block.timestamp && _poolEndTime > poolStartTime,
            "GDEXRewardPool: End time lt current timestamp or start time"
        );
        poolEndTime = _poolEndTime;
    }

    function withdraw(uint256 _pid, uint256 _amount) external {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "GDEXRewardPool: Amount gt available");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accRewardSharePerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            totalPendingShare = totalPendingShare.sub(_pending);
            safeRewardTokenShareTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardSharePerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) updatePool(pid);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) return;
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
            uint256 _reward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            totalPendingShare = totalPendingShare.add(_reward);
            pool.accRewardSharePerShare = pool.accRewardSharePerShare.add(_reward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    function checkPoolDuplicate(IERC20 _token) private view {
        uint256 len = poolInfo.length;
        for (uint256 pid = 0; pid < len; ++pid) require(poolInfo[pid].token != _token, "GDEXRewardPool: Existing pool");
    }

    function safeRewardTokenShareTransfer(address _to, uint256 _amount) private {
        uint256 _rewardBal = rewardToken.balanceOf(address(this));
        if (_rewardBal > 0) {
            if (_amount > _rewardBal) rewardToken.safeTransfer(_to, _rewardBal);
            else rewardToken.safeTransfer(_to, _amount);
        }
    }


    function depositFundsForInterval(uint256 _amount) external onlyOperator returns (uint256) {
        return _depositFundsForInterval(_amount);
    }

    function _depositFundsForInterval(uint256 _amount) private returns (uint256) {
        require(_amount > 0, "GDEXRewardPool: Distribute amount is zero");
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 previousSharesPerSecond = sharesPerSecond;
        uint256 timeDiff;
        uint256 amountDiff;
        uint256 amountToDistribute;
        uint256 newSharesPerSecond;
        
        if (block.timestamp >= nextDepositFundsTime) {
            timeDiff = block.timestamp - nextDepositFundsTime;
            amountDiff = timeDiff * previousSharesPerSecond;
            amountToDistribute = _amount - amountDiff;
            nextDepositFundsTime = (block.timestamp + depositFundsInterval) / depositFundsInterval * depositFundsInterval;
            newSharesPerSecond = amountToDistribute / (nextDepositFundsTime - block.timestamp);

        } else {
            timeDiff = nextDepositFundsTime - block.timestamp;
            amountDiff = timeDiff * previousSharesPerSecond;
            amountToDistribute = _amount + amountDiff;
            nextDepositFundsTime = (block.timestamp + (2 * depositFundsInterval)) / depositFundsInterval * depositFundsInterval;
            newSharesPerSecond = amountToDistribute / (nextDepositFundsTime - block.timestamp);
        }

        sharesPerSecond = newSharesPerSecond;

        emit DepositedFunds(msg.sender, _amount, sharesPerSecond);

        return sharesPerSecond;
    }


    modifier onlyOperator() {
        require(operator == msg.sender, "GDEXRewardPool: Caller is not operator");
        _;
    }
}

