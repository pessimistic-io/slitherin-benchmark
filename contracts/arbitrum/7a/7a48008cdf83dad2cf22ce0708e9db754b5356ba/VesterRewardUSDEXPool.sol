// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./ReentrancyGuard.sol";
import "./Initializable.sol";



interface IStakingToken {  
    function burn(address from, uint256 amount) external returns (bool);
}


contract VesterRewardUSDEXPool is ReentrancyGuard, Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 availableToClaimRewardsAfterRelease;
        uint256 availableToRelease;
    }

    struct PoolInfo {
        IERC20 token;
        uint256 allocPoint;
        uint256 lastRewardTime;
        uint256 accRewardSharePerShare;
        bool isStarted;
    }

    IERC20 public rewardToken;
    IERC20 public releaseToken;
    address public operator;
    uint256 public totalAllocPoint = 0;
    uint256 public poolStartTime;
    uint256 public poolEndTime;
    uint256 public sharesPerSecond;
    uint256 public totalPendingShare;

    uint256 public totalStakedAmount;

    EnumerableSet.AddressSet private _stakers;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    mapping (address => bool) public isHandler;

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

    event Deposit(address indexed sender, address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event DepositedRelease(address indexed sender, address token, uint256 amount);
    event ClaimedRewards(address user, uint256 amount);
    event ClaimedRelease(address user, uint256 amount);


    function stakers(uint256 index) external view returns (address) {
        return _stakers.at(index);
    }

    function stakersContains(address user) external view returns (bool) {
        return _stakers.contains(user);
    }

    function stakersLength() external view returns (uint256) {
        return _stakers.length();
    }

    function stakersList(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory output) {
        uint256 _stakersLength = _stakers.length();
        if (offset >= _stakersLength) return new address[](0);
        uint256 to = offset + limit;
        if (_stakersLength < to) to = _stakersLength;
        output = new address[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = _stakers.at(offset + i);
    }

    constructor(
        address _rewardToken,
        address _releaseToken
    ) {
        require(_rewardToken != address(0), "VesterRewardUSDEXPool: RewardToken is zero address");
        require(_releaseToken != address(0), "VesterRewardPool: ReleaseToken is zero address");
        rewardToken = IERC20(_rewardToken);
        releaseToken = IERC20(_releaseToken);
        operator = msg.sender;
    }

    function initialize(uint256 _poolStartTime, uint256 _poolEndTime) external initializer returns (bool) {
        require(_poolStartTime > block.timestamp, "VesterRewardUSDEXPool: Start time lte current timestamp");
        require(_poolEndTime > _poolStartTime, "VesterRewardUSDEXPool: End time lte start time");
        poolStartTime = _poolStartTime;
        poolEndTime = _poolEndTime;

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

    function deposit(uint256 _pid, uint256 _amount) external returns (bool) {
        _deposit(msg.sender, _pid, _amount);
        return true;
    }

    function depositForAccount(address _account, uint256 _pid, uint256 _amount) external onlyHandler returns (bool) {
        _deposit(_account, _pid, _amount);
        return true;
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
            require(_token != rewardToken, "VesterRewardUSDEXPool: Recover token eq RewardToken");
            for (uint256 pid = 0; pid < poolLength; pid++) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "VesterRewardUSDEXPool: Recover token eq pool token");
            }
        } else if (_token == rewardToken) {
            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            require(rewardBalance > totalPendingShare, "VesterRewardUSDEXPool: No reward tokens to recover");
            require(
                amount <= rewardBalance.sub(totalPendingShare),
                "VesterRewardUSDEXPool: Amount gt possible to recover"
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
        require(_operator != address(0), "VesterRewardUSDEXPool: Operator is zero address");
        operator = _operator;
    }

    function setHandler(address _handler, bool _isActive) external onlyOperator {
        isHandler[_handler] = _isActive;
    }

    function setSharesPerSecond(uint256 _sharesPerSecond) external onlyOperator {
        sharesPerSecond = _sharesPerSecond;
    }

    function setPoolEndTime(uint256 _poolEndTime) external onlyOperator {
        require(
            _poolEndTime >= block.timestamp && _poolEndTime > poolStartTime,
            "VesterRewardUSDEXPool: End time lt current timestamp or start time"
        );
        poolEndTime = _poolEndTime;
    }

    function withdraw(uint256 _pid, uint256 _amount) external {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "VesterRewardUSDEXPool: Amount gt available");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accRewardSharePerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            totalPendingShare = totalPendingShare.sub(_pending);
            user.availableToClaimRewardsAfterRelease = user.availableToClaimRewardsAfterRelease.add(_pending);
        }
        uint256 rewardAmount = user.availableToClaimRewardsAfterRelease;
        user.availableToClaimRewardsAfterRelease = 0;
        if (rewardAmount > 0) safeRewardTokenShareTransfer(_sender, rewardAmount);
        emit RewardPaid(_sender, rewardAmount);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if (user.amount == 0) _stakers.remove(_sender);
            totalStakedAmount = totalStakedAmount.sub(_amount);
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
        for (uint256 pid = 0; pid < len; ++pid) require(poolInfo[pid].token != _token, "VesterRewardUSDEXPool: Existing pool");
    }

    function safeRewardTokenShareTransfer(address _to, uint256 _amount) private {
        uint256 _rewardBal = rewardToken.balanceOf(address(this));
        if (_rewardBal > 0) {
            if (_amount > _rewardBal) rewardToken.safeTransfer(_to, _rewardBal);
            else rewardToken.safeTransfer(_to, _amount);
        }
    }

    function claimRewards(uint256 _pid) external nonReentrant returns (bool) {
        _claimRewards(_pid, msg.sender);
        return true;
    }

    function claimReleaseTokens(uint256 _pid) external nonReentrant returns (bool) {
        _claimReleaseTokens(_pid, msg.sender);
        return true;
    }

    function depositFundsForRelease(uint256 _pid, uint256 _releaseAmount) external onlyOperator returns (bool) {
        require(totalStakedAmount > 0, "VesterRewardUSDEXPool: Total staked amount is zero");
        PoolInfo storage pool = poolInfo[_pid];
        updatePool(_pid);

        releaseToken.safeTransferFrom(msg.sender, address(this), _releaseAmount);
        uint256 releaseTokensForShare = _releaseAmount.mul(1e18).div(totalStakedAmount);
        uint256 _stakersLength = _stakers.length();

        for (uint256 i = _stakersLength - 1; i >= 0; i--) {
            UserInfo storage user = userInfo[_pid][_stakers.at(i)];
            uint256 _pending = user.amount.mul(pool.accRewardSharePerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                totalPendingShare = totalPendingShare.sub(_pending);
                user.availableToClaimRewardsAfterRelease = user.availableToClaimRewardsAfterRelease.add(_pending);
            }
            user.rewardDebt = user.amount.mul(pool.accRewardSharePerShare).div(1e18);

            uint256 releaseAmount_ = user.amount.mul(releaseTokensForShare).div(1e18);
            IStakingToken(address(pool.token)).burn(address(this), releaseAmount_);

            user.amount = user.amount.sub(releaseAmount_);
            user.availableToRelease = user.availableToRelease.add(releaseAmount_);
            if (user.amount == 0) _stakers.remove(_stakers.at(i));
            totalStakedAmount = totalStakedAmount.sub(releaseAmount_);
            if (i == 0) break;
        }

        emit DepositedRelease(msg.sender, address(releaseToken), _releaseAmount);
        return true;
    }

    function _deposit(address _account, uint256 _pid, uint256 _amount) private {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accRewardSharePerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                totalPendingShare = totalPendingShare.sub(_pending);
                user.availableToClaimRewardsAfterRelease = user.availableToClaimRewardsAfterRelease.add(_pending);
            }
            uint256 rewardAmount = user.availableToClaimRewardsAfterRelease;
            user.availableToClaimRewardsAfterRelease = 0;
            if (rewardAmount > 0) safeRewardTokenShareTransfer(_account, rewardAmount);
            emit RewardPaid(_account, rewardAmount);
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            _stakers.add(_account);
            totalStakedAmount = totalStakedAmount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardSharePerShare).div(1e18);
        emit Deposit(_sender, _account, _pid, _amount);
    }

    function _claimRewards(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);

        uint256 _pending = user.amount.mul(pool.accRewardSharePerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            totalPendingShare = totalPendingShare.sub(_pending);
            user.availableToClaimRewardsAfterRelease = user.availableToClaimRewardsAfterRelease.add(_pending);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardSharePerShare).div(1e18);
        uint256 rewardAmount = user.availableToClaimRewardsAfterRelease;
        require(rewardAmount > 0, "VesterRewardUSDEXPool: Amount reward tokens is zero");
        user.availableToClaimRewardsAfterRelease = 0;
        rewardToken.safeTransfer(_user, rewardAmount);
        emit ClaimedRewards(_user, rewardAmount);
    }

    function _claimReleaseTokens(uint256 _pid, address _user) private {
        UserInfo storage user = userInfo[_pid][_user];
        uint256 releaseAmount = user.availableToRelease;
        require(releaseAmount > 0, "VesterRewardUSDEXPool: Amount release tokens is zero");
        user.availableToRelease = 0;
        releaseToken.safeTransfer(_user, releaseAmount);
        emit ClaimedRelease(_user, releaseAmount);
    }

    function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyOperator returns (bool) {
        _token.safeTransfer(_to, _amount);
        return true;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "VesterRewardUSDEXPool: Caller is not operator");
        _;
    }

    modifier onlyHandler() {
        require(isHandler[msg.sender], "VesterRewardPool: Caller is not handler");
        _;
    }
}

