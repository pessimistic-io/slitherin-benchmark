// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./ReentrancyGuard.sol";
import "./Initializable.sol";


interface IStakingToken {  
    function burn(address from, uint256 amount) external returns (bool);
}


contract VesterRewardPool is ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount;
        uint256 availableToClaimRewards;
        uint256 availableToRelease;
    }

    uint256 public constant PRECISION = 10 ** 18;

    IERC20 public stakingToken;
    IERC20 public releaseToken;
    IERC20 public rewardToken;

    uint256 public lastRewardTime;

    uint256 public poolStartTime;
    uint256 public poolEndTime;
    uint256 public rewardsPerSecondForShare;

    EnumerableSet.AddressSet private _stakers;

    mapping(address => UserInfo) public userInfo;

    mapping (address => bool) public isHandler;

    uint256 public totalStakedAmount;

    uint256 public epochInterval;

    address public operator;


    event Staked(address indexed sender, address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event ClaimedRewards(address indexed user, address indexed token, uint256 amount);
    event ClaimedRelease(address indexed user, address indexed token, uint256 amount);
    event DepositedRewards(address indexed owner, address indexed token, uint256 amount);
    event DepositedReleaseAndRewards(address indexed owner, address indexed releaseToken, uint256 releaseAmount, address indexed rewardToken, uint256 rewardAmount);


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
        address _stakingToken,
        address _releaseToken,
        address _rewardToken,
        uint256 _rewardsPerSecondForShare,
        uint256 _epochInterval
    ) {
        require(_stakingToken != address(0), "VesterRewardPool: StakingToken is zero address");
        require(_releaseToken != address(0), "VesterRewardPool: ReleaseToken is zero address");
        require(_rewardToken != address(0), "VesterRewardPool: RewardToken is zero address");
        require(_epochInterval > 0, "VesterRewardPool: EpochInterval is zero");
        stakingToken = IERC20(_stakingToken);
        releaseToken = IERC20(_releaseToken);
        rewardToken = IERC20(_rewardToken);
        rewardsPerSecondForShare = _rewardsPerSecondForShare;
        epochInterval = _epochInterval;
        operator = msg.sender;
    }
     
    function initialize(uint256 _poolStartTime, uint256 _poolEndTime) external initializer returns (bool) {
        require(_poolStartTime > block.timestamp, "VesterRewardPool: Start time lte current timestamp");
        require(_poolEndTime > _poolStartTime, "VesterRewardPool: End time lte start time");
        poolStartTime = _poolStartTime;
        poolEndTime = _poolEndTime;
        lastRewardTime = _poolStartTime;

        return true;
    }

    function setOperator(address _operator) external onlyOperator {
        require(_operator != address(0), "VesterRewardPool: Operator is zero address");
        operator = _operator;
    }

    function setHandler(address _handler, bool _isActive) external onlyOperator {
        isHandler[_handler] = _isActive;
    }

    function setRewardsPerSecondForShare(uint256 _rewardsPerSecondForShare) external onlyOperator {
        rewardsPerSecondForShare = _rewardsPerSecondForShare;
    }

    function setEpochInterval(uint256 _epochInterval) external onlyOperator {
        require(_epochInterval > 0, "VesterRewardPool: EpochInterval is zero");
        epochInterval = _epochInterval;
    }

    function setPoolEndTime(uint256 _poolEndTime) external onlyOperator {
        require(
            _poolEndTime >= block.timestamp && _poolEndTime > poolStartTime,
            "VesterRewardPool: End time lt current timestamp or start time"
        );
        poolEndTime = _poolEndTime;
    }

    function estimateEpochRewardsAmount() public view returns (uint256) {
        if (lastRewardTime + epochInterval > block.timestamp) return 0; 
        if (totalStakedAmount == 0) return 0; 

        uint256 intervals = (block.timestamp - lastRewardTime) / epochInterval;
        return rewardsPerSecondForShare * intervals * epochInterval * totalStakedAmount / PRECISION; 
    }


    function stake(uint256 _amount) external returns (bool) {
        _stake(msg.sender, _amount);
        return true;
    }


    function stakeForAccount(address _account, uint256 _amount) external onlyHandler returns (bool) {
        _stake(_account, _amount);
        return true;
    }

    function unstake(uint256 _amount) external returns (bool) {
        address _sender = msg.sender;
        UserInfo storage user = userInfo[_sender];
        if (_amount == 0) return false;
        require(user.amount >= _amount, "VesterRewardPool: Amount gt available");

        user.amount = user.amount - _amount;
        totalStakedAmount -= _amount;
        stakingToken.safeTransfer(_sender, _amount);
        if (user.amount == 0) _stakers.remove(_sender);

        emit Unstaked(_sender, _amount);
        return true;
    }
    
    function claimRewards(uint256 _amount) external nonReentrant returns (bool) {
        _claimRewards(msg.sender, _amount);
        return true;
    }

    function claimReleaseTokens() external nonReentrant returns (bool) {
        _claimReleaseTokens(msg.sender);
        return true;
    }

    function depositRewardsForEpoch(uint256 _amount) external onlyOperator returns (bool) {
        _depositRewardsForEpoch(_amount);
        return true;
    }

    function depositFundsForReleaseAndRewards(uint256 _releaseAmount, uint256 _rewardAmount) external onlyOperator returns (bool) {
        require(totalStakedAmount > 0, "VesterRewardPool: Total staked amount is zero");
        uint256 _distributeRewardAmount = estimateEpochRewardsAmount();
        require(_distributeRewardAmount > 0, "VesterRewardPool: Epoch is no ended");
        require(_rewardAmount >= _distributeRewardAmount, "VesterRewardPool: Total reward amount is lt estimation");
        rewardToken.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        releaseToken.safeTransferFrom(msg.sender, address(this), _releaseAmount);

        uint256 rewardTime = ((block.timestamp - lastRewardTime) / epochInterval) * epochInterval;

        uint256 releaseTokensForShare = _releaseAmount * PRECISION / totalStakedAmount;

        uint256 _stakersLength = _stakers.length();


        for (uint256 i = _stakersLength - 1; i >= 0; i--) {
            UserInfo storage info = userInfo[_stakers.at(i)];

            uint256 rewardAmount_ = info.amount * rewardsPerSecondForShare * rewardTime / PRECISION;
            info.availableToClaimRewards += rewardAmount_;


            uint256 releaseAmount_ = info.amount * releaseTokensForShare / PRECISION;

            IStakingToken(address(stakingToken)).burn(address(this), releaseAmount_);
            info.amount -= releaseAmount_;
            info.availableToRelease += releaseAmount_;
            if (info.amount == 0) _stakers.remove(_stakers.at(i));
            totalStakedAmount -= releaseAmount_;
            if (i == 0) break;
        }

        lastRewardTime = (block.timestamp / epochInterval) * epochInterval;

        emit DepositedReleaseAndRewards(msg.sender, address(releaseToken), _releaseAmount, address(rewardToken), _rewardAmount);
        return true;
    }

    function _stake(address _account, uint256 _amount) private {
        address _sender = msg.sender;
        UserInfo storage user = userInfo[_account];
        if (_amount == 0) return;

        stakingToken.safeTransferFrom(_sender, address(this), _amount);
        user.amount = user.amount + _amount;
        _stakers.add(_account);
        totalStakedAmount += _amount;

        emit Staked(_sender, _account, _amount);
    }

    function _depositRewardsForEpoch(uint256 _amount) private {
        uint256 _distributeAmount = estimateEpochRewardsAmount();
        require(_distributeAmount > 0, "VesterRewardPool: Distribute amount is zero");
        require(_amount >= _distributeAmount, "VesterRewardPool: Total reward amount is lt estimation");
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 rewardTime = ((block.timestamp - lastRewardTime) / epochInterval) * epochInterval;

        _allocateRewards(rewardTime);
        lastRewardTime = (block.timestamp / epochInterval) * epochInterval;

        emit DepositedRewards(msg.sender, address(rewardToken), _amount);
    }

    function _allocateRewards(uint256 _rewardTime) private {
        uint256 _stakersLength = _stakers.length();

        for (uint256 i = 0; i < _stakersLength; i++) {
            UserInfo storage info = userInfo[_stakers.at(i)];
            uint256 rewardAmount = info.amount * rewardsPerSecondForShare * _rewardTime / PRECISION;
            info.availableToClaimRewards += rewardAmount;
        }
    }

    function _claimRewards(address _user, uint256 _amount) private {
        UserInfo storage info = userInfo[_user];
        require(_amount <= info.availableToClaimRewards, "VesterRewardPool: Amount exceeds available to claim");
        info.availableToClaimRewards -= _amount;
        rewardToken.safeTransfer(_user, _amount);
        emit ClaimedRewards(_user, address(rewardToken), _amount);
    }

    function _claimReleaseTokens(address _user) private {
        UserInfo storage info = userInfo[_user];
        uint256 releaseAmount = info.availableToRelease;
        require(releaseAmount > 0, "VesterRewardPool: Amount release tokens to claim is zero");
        info.availableToRelease = 0;
        releaseToken.safeTransfer(_user, releaseAmount);
        emit ClaimedRelease(_user, address(releaseToken), releaseAmount);
    }

    function foreignTokensRecover(IERC20 _token, uint256 _amount, address _to) external onlyOperator returns (bool) {
        _token.safeTransfer(_to, _amount);
        return true;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "VesterRewardPool: Caller is not operator");
        _;
    }

    modifier onlyHandler() {
        require(isHandler[msg.sender], "VesterRewardPool: Caller is not handler");
        _;
    }
}

