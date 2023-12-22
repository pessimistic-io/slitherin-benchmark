// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {ILevelNormalVesting} from "./ILevelNormalVesting.sol";

/**
 * @title LevelDaoOmniStaking
 * @author Level
 * @notice Stake `stakeToken` to earn LGO tokens. The reward is allocated weekly, which we called an epoch.
 */
contract LevelDaoOmniStaking is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct EpochInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 allocationTime;
        uint256 totalAccShare;
        uint256 lastUpdateAccShareTime;
        uint256 totalReward;
    }

    struct UserInfo {
        /// @notice staked amount of user in epoch
        uint256 amount;
        uint256 claimedReward;
        /// @notice accumulated amount, calculated by total of deposited amount multiplied with deposited time
        uint256 accShare;
        uint256 lastUpdateAccShareTime;
    }

    uint256 public constant MIN_EPOCH_DURATION = 1 days;

    IERC20 public LGO;
    IERC20 public stakeToken;

    bool public enableNextEpoch;

    address public distributor;

    uint256 public currentEpoch;
    /// @notice start time of the current epoch
    uint256 public lastEpochTimestamp;
    uint256 public epochDuration;
    uint256 public totalStaked;

    mapping(uint256 epoch => EpochInfo) public epochs;
    mapping(address userAddress => mapping(uint256 epoch => UserInfo)) public users;
    mapping(address userAddress => uint256) public stakedAmounts;
    /// @notice list of epoch in which user updated their staked amount (stake or unstake)
    mapping(address userAddress => uint256[]) public userSnapshotEpochs;

    ILevelNormalVesting public normalVestingLVL;
    address public stakingHelper;
    address public claimHelper;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _stakeToken, address _lgo, uint256 _startTime) external initializer {
        if (_stakeToken == address(0)) revert ZeroAddress();
        if (_lgo == address(0)) revert ZeroAddress();
        if (_startTime < block.timestamp) revert InvalidStartTime();
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        stakeToken = IERC20(_stakeToken);
        LGO = IERC20(_lgo);
        epochDuration = 7 days;
        // Start first epoch
        lastEpochTimestamp = _startTime;
        epochs[currentEpoch].startTime = _startTime;
        epochs[currentEpoch].lastUpdateAccShareTime = _startTime;
        emit EpochStarted(currentEpoch, _startTime);
    }

    modifier onlyDistributorOrOwner() {
        _checkDistributorOrOwner();
        _;
    }

    // =============== VIEW FUNCTIONS ===============
    function getNextEpochStartTime() public view returns (uint256) {
        return lastEpochTimestamp + epochDuration;
    }

    function pendingRewards(uint256 _epoch, address _user) public view returns (uint256 _pendingRewards) {
        EpochInfo memory _epochInfo = epochs[_epoch];
        if (_epochInfo.endTime != 0 && _epochInfo.totalReward != 0) {
            UserInfo memory _userInfo = users[_user][_epoch];
            uint256 _stakedAmount = getStakedAmountByEpoch(_epoch, _user);
            uint256 _lastUpdateAccShareTime = _userInfo.lastUpdateAccShareTime;
            if (_lastUpdateAccShareTime == 0) {
                _lastUpdateAccShareTime = _epochInfo.startTime;
            }
            uint256 _userShare = _userInfo.accShare + ((_epochInfo.endTime - _lastUpdateAccShareTime) * _stakedAmount);
            if (_epochInfo.totalAccShare != 0) {
                _pendingRewards =
                    ((_userShare * _epochInfo.totalReward) / _epochInfo.totalAccShare) - _userInfo.claimedReward;
            }
        }
    }

    /**
     * @dev searches a staked amount by epoch. Uses binary search.
     * @param _epoch the epoch being searched
     * @param _user the user for which the snapshot is being searched
     * @return The staked amount
     */
    function getStakedAmountByEpoch(uint256 _epoch, address _user) public view returns (uint256) {
        uint256[] storage _snapshotEpochs = userSnapshotEpochs[_user];
        uint256 _snapshotsCount = _snapshotEpochs.length;
        if (_snapshotsCount == 0) {
            return 0;
        }
        // First check most recent epoch
        if (_snapshotEpochs[_snapshotsCount - 1] <= _epoch) {
            return stakedAmounts[_user];
        }
        // Next check first epoch
        if (_snapshotEpochs[0] > _epoch) {
            return 0;
        }

        uint256 _lower = 0;
        uint256 _upper = _snapshotsCount - 1;
        while (_upper > _lower) {
            uint256 _center = _upper - (_upper - _lower) / 2; // ceil, avoiding overflow
            uint256 _centerEpoch = _snapshotEpochs[_center];
            if (_centerEpoch == _epoch) {
                return users[_user][_centerEpoch].amount;
            } else if (_centerEpoch < _epoch) {
                _lower = _center;
            } else {
                _upper = _center - 1;
            }
        }
        return users[_user][_snapshotEpochs[_lower]].amount;
    }

    // =============== USER FUNCTIONS ===============

    function stake(address _to, uint256 _amount) external whenNotPaused nonReentrant {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        _updateCurrentEpoch();
        _updateUser(_to, _amount, true);
        totalStaked += _amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _to, currentEpoch, _amount);
    }

    function unstake(address _to, uint256 _amount) external nonReentrant {
        _unstake(msg.sender, _to, _amount);
    }

    function claimRewards(uint256 _epoch, address _to) external whenNotPaused nonReentrant {
        _claimRewards(msg.sender, _epoch, _to);
    }

    /**
     * @notice Support multiple claim, only `claimHelper` can call this function.
     */
    function claimRewardsOnBehalf(address _user, uint256 _epoch, address _to)
        external
        virtual
        whenNotPaused
        nonReentrant
    {
        if (msg.sender != claimHelper) revert Unauthorized();
        _claimRewards(_user, _epoch, _to);
    }

    /// @notice end current epoch and start a new one. Note that the reward is not available at this moment
    function nextEpoch() external {
        if (!enableNextEpoch) revert NotEnableNextEpoch();
        uint256 _nextEpochStartTime = getNextEpochStartTime();
        uint256 _currentTime = block.timestamp;
        if (_currentTime < _nextEpochStartTime) revert TooEarly();

        _updateCurrentEpoch();
        epochs[currentEpoch].endTime = _currentTime;
        lastEpochTimestamp = _nextEpochStartTime;
        emit EpochEnded(currentEpoch, _nextEpochStartTime);

        currentEpoch++;
        epochs[currentEpoch].startTime = _currentTime;
        epochs[currentEpoch].lastUpdateAccShareTime = _currentTime;
        emit EpochStarted(currentEpoch, _nextEpochStartTime);
    }

    /// @notice allocate LGO tokens to selected epoch. Epoch MUST be ended but not allocated
    function allocateReward(uint256 _epoch, uint256 _rewardAmount) external {
        if (msg.sender != stakingHelper) revert Unauthorized();
        EpochInfo memory _epochInfo = epochs[_epoch];
        if (_epochInfo.endTime == 0) revert NotEnded();
        if (_epochInfo.allocationTime > 0) revert Allocated();
        if (_rewardAmount == 0) revert ZeroReward();
        _epochInfo.totalReward = _rewardAmount;
        _epochInfo.allocationTime = block.timestamp;
        epochs[_epoch] = _epochInfo;
        LGO.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        emit RewardAllocated(_epoch, _rewardAmount);
    }

    // =============== RESTRICTED ===============
    function setEnableNextEpoch(bool _enable) external onlyDistributorOrOwner {
        enableNextEpoch = _enable;
        emit EnableNextEpochSet(_enable);
    }

    function setEpochDuration(uint256 _epochDuration) external onlyOwner {
        if (_epochDuration < MIN_EPOCH_DURATION) revert InvalidDuration();
        EpochInfo memory _epochInfo = epochs[currentEpoch];
        if (_epochInfo.startTime + _epochDuration < block.timestamp) revert InvalidDuration();
        epochDuration = _epochDuration;

        emit EpochDurationSet(_epochDuration);
    }

    function setStakingHelper(address _stakingHelper) external onlyOwner {
        stakingHelper = _stakingHelper;
        emit StakingHelperSet(_stakingHelper);
    }

    function setClaimHelper(address _claimHelper) external onlyOwner {
        claimHelper = _claimHelper;
        emit ClaimHelperSet(_claimHelper);
    }

    function setNormalVestingLVL(address _normalVestingLVL) external onlyOwner {
        if (_normalVestingLVL == address(0)) revert ZeroAddress();
        normalVestingLVL = ILevelNormalVesting(_normalVestingLVL);
        emit LevelNormalVestingSet(_normalVestingLVL);
    }

    function setDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) revert ZeroAddress();
        distributor = _distributor;
        emit DistributorSet(distributor);
    }

    function pause() external onlyDistributorOrOwner {
        _pause();
    }

    function unpause() external onlyDistributorOrOwner {
        _unpause();
    }

    // =============== INTERNAL FUNCTIONS ===============
    function _checkDistributorOrOwner() internal view {
        if (msg.sender != distributor && msg.sender != owner()) revert Unauthorized();
    }

    function _updateCurrentEpoch() internal {
        EpochInfo memory _epochInfo = epochs[currentEpoch];
        uint256 _currentTime = block.timestamp;
        if (_currentTime >= _epochInfo.startTime) {
            uint256 _elapsedTime = _currentTime - _epochInfo.lastUpdateAccShareTime;
            _epochInfo.totalAccShare += _elapsedTime * totalStaked;
            _epochInfo.lastUpdateAccShareTime = _currentTime;
            epochs[currentEpoch] = _epochInfo;
        }
    }

    function _updateUser(address _user, uint256 _amount, bool _isIncrease) internal {
        UserInfo memory _userSnapshot = users[_user][currentEpoch];
        EpochInfo memory _epochInfo = epochs[currentEpoch];
        if (_userSnapshot.lastUpdateAccShareTime == 0) {
            userSnapshotEpochs[_user].push(currentEpoch);
        }
        uint256 _currentTime = block.timestamp;
        uint256 _currentStakedAmounts = stakedAmounts[_user];
        if (_currentTime >= _epochInfo.startTime) {
            uint256 _lastUpdateAccShareTime = _userSnapshot.lastUpdateAccShareTime;
            if (_userSnapshot.lastUpdateAccShareTime < _epochInfo.startTime) {
                _lastUpdateAccShareTime = _epochInfo.startTime;
            }
            uint256 _elapsedTime = _currentTime - _lastUpdateAccShareTime;
            _userSnapshot.accShare += _elapsedTime * _currentStakedAmounts;
            _userSnapshot.lastUpdateAccShareTime = _currentTime;
        }
        stakedAmounts[_user] = _isIncrease ? _currentStakedAmounts + _amount : _currentStakedAmounts - _amount;
        _userSnapshot.amount = stakedAmounts[_user];
        users[_user][currentEpoch] = _userSnapshot;
    }

    /// @notice claim rewards as LGO token
    function _claimRewards(address _user, uint256 _epoch, address _to) internal {
        if (_user == address(0)) revert ZeroAddress();
        if (_to == address(0)) revert ZeroAddress();
        uint256 _pendingReward = pendingRewards(_epoch, _user);
        if (_pendingReward != 0) {
            users[_user][_epoch].claimedReward += _pendingReward;
            LGO.safeTransfer(_to, _pendingReward);
            emit Claimed(_user, _to, _epoch, _pendingReward);
        }
    }

    function _unstake(address _user, address _to, uint256 _amount) internal {
        if (_user == address(0)) revert ZeroAddress();
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        uint256 _reservedForVesting = 0;
        if (address(normalVestingLVL) != address(0)) {
            _reservedForVesting = normalVestingLVL.getReservedAmount(_user);
        }
        if (_amount + _reservedForVesting > stakedAmounts[_user]) revert InsufficientStakedAmount();
        _updateCurrentEpoch();
        _updateUser(_user, _amount, false);
        totalStaked -= _amount;
        stakeToken.safeTransfer(_to, _amount);
        emit Unstaked(_user, _to, currentEpoch, _amount);
    }

    // =============== ERRORS ===============
    error ZeroAddress();
    error ZeroAmount();
    error ZeroReward();
    error InvalidStartTime();
    error InvalidDuration();
    error InsufficientStakedAmount();
    error NotEnableNextEpoch();
    error Unauthorized();
    error TooEarly();
    error NotEnded();
    error Allocated();

    // =============== EVENTS ===============
    event EnableNextEpochSet(bool _enable);
    event EpochDurationSet(uint256 _epochDuration);
    event DistributorSet(address indexed _distributor);
    event StakingHelperSet(address _stakingHelper);
    event ClaimHelperSet(address _claimHelper);
    event LevelNormalVestingSet(address _normalVestingLVL);
    event EpochStarted(uint256 indexed _epoch, uint256 _startTime);
    event EpochEnded(uint256 indexed _epoch, uint256 _endTime);
    event RewardAllocated(uint256 indexed _epoch, uint256 _amount);
    event Staked(address indexed _from, address indexed _to, uint256 _epoch, uint256 _stakedAmount);
    event Unstaked(address indexed _from, address indexed _to, uint256 _epoch, uint256 _amount);
    event Claimed(address indexed _from, address indexed _to, uint256 _epoch, uint256 _amount);
}

