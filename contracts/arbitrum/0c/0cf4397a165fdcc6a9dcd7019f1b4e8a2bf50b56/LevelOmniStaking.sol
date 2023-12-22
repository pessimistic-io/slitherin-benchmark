// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {Initializable} from "./Initializable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {IBurnableERC20} from "./IBurnableERC20.sol";
import {StakingReserve} from "./StakingReserve.sol";

/**
 * @title LevelOmniStaking
 * @author Level
 * @notice Stake protocol token to earn protocol revenue, in the form of LLP token. The reward is allocated weekly, which we called an epoch.
 * The protocol fee is collected to this contract in a daily basis.
 * Whenever an epoch ended, admin can move the collected fee between chains based on the staked amount on each chain,
 * then she call the allocate method to start distributing the reward.
 * User can choose to claim their reward as LLP token or swap to one of available tokens.
 */
contract LevelOmniStaking is Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable, StakingReserve {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBurnableERC20;

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

    uint256 public constant STAKING_TAX_PRECISION = 1000;
    uint256 public constant STAKING_TAX = 4; // 0.4%
    uint256 public constant MIN_EPOCH_DURATION = 1 days;

    IBurnableERC20 public stakeToken;

    bool public enableNextEpoch;

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
    /// @notice list of tokens to which user can convert their reward. Note that they MUST pay the swap fee
    mapping(address userAddress => bool) public claimableTokens;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _pool,
        address _stakeToken,
        address _llp,
        address _weth,
        address _ethUnwrapper,
        uint256 _startTime
    ) external initializer {
        require(_stakeToken != address(0), "Invalid address");
        require(_startTime >= block.timestamp, "Invalid start time");
        __Pausable_init();
        __ReentrancyGuard_init();
        __StakingReserve_init(_pool, _llp, _weth, _ethUnwrapper);
        stakeToken = IBurnableERC20(_stakeToken);
        epochDuration = 7 days;
        // Start first epoch
        lastEpochTimestamp = _startTime;
        epochs[currentEpoch].startTime = _startTime;
        epochs[currentEpoch].lastUpdateAccShareTime = _startTime;
        emit EpochStarted(currentEpoch, _startTime);
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
            _pendingRewards =
                ((_userShare * _epochInfo.totalReward) / _epochInfo.totalAccShare) - _userInfo.claimedReward;
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
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        uint256 _taxAmount = (_amount * STAKING_TAX) / STAKING_TAX_PRECISION;
        uint256 _stakedAmount = _amount - _taxAmount;
        _updateCurrentEpoch();
        _updateUser(_to, _stakedAmount, true);
        totalStaked += _stakedAmount;
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
        if (_taxAmount != 0) {
            stakeToken.burn(_taxAmount);
        }
        emit Staked(msg.sender, _to, currentEpoch, _stakedAmount, _taxAmount);
    }

    function unstake(address _to, uint256 _amount) external whenNotPaused nonReentrant {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        address _sender = msg.sender;
        require(stakedAmounts[_sender] >= _amount, "Insufficient staked amount");
        _updateCurrentEpoch();
        _updateUser(_sender, _amount, false);
        totalStaked -= _amount;
        stakeToken.safeTransfer(_to, _amount);
        emit Unstaked(_sender, _to, currentEpoch, _amount);
    }

    /// @notice claim rewards as LLP token
    function claimRewards(uint256 _epoch, address _to) external whenNotPaused nonReentrant {
        require(_to != address(0), "Invalid address");
        address _sender = msg.sender;
        uint256 _pendingReward = pendingRewards(_epoch, _sender);
        if (_pendingReward != 0) {
            users[_sender][_epoch].claimedReward += _pendingReward;
            _safeTransferToken(address(LLP), _to, _pendingReward);
            emit Claimed(_sender, _to, _epoch, _pendingReward);
        }
    }

    /// @notice claim then swap LLP token to one of the claimable tokens
    function claimRewardsToSingleToken(uint256 _epoch, address _to, address _tokenOut, uint256 _minAmountOut)
        external
        whenNotPaused
        nonReentrant
    {
        require(_to != address(0), "Invalid address");
        require(claimableTokens[_tokenOut], "!claimableTokens");
        address _sender = msg.sender;
        uint256 _pendingReward = pendingRewards(_epoch, _sender);
        if (_pendingReward != 0) {
            users[_sender][_epoch].claimedReward += _pendingReward;
            uint256 _amountOut = _convertLLPToToken(_to, _pendingReward, _tokenOut, _minAmountOut);
            emit SingleTokenClaimed(_sender, _to, _epoch, _pendingReward, _tokenOut, _amountOut);
        }
    }

    /// @notice end current epoch and start a new one. Note that the reward is not available at this moment
    function nextEpoch() external {
        require(enableNextEpoch, "!enableNextEpoch");
        uint256 _nextEpochStartTime = getNextEpochStartTime();
        uint256 _currentTime = block.timestamp;
        require(_currentTime >= _nextEpochStartTime, "< next start time");

        _updateCurrentEpoch();
        epochs[currentEpoch].endTime = _currentTime;
        lastEpochTimestamp = _nextEpochStartTime;
        emit EpochEnded(currentEpoch, _nextEpochStartTime);

        currentEpoch++;
        epochs[currentEpoch].startTime = _currentTime;
        epochs[currentEpoch].lastUpdateAccShareTime = _currentTime;
        emit EpochStarted(currentEpoch, _nextEpochStartTime);
    }

    /// @notice convert ALL fee tokens to LLP token then allocate to selected epoch. Epoch MUST be ended but not allocated
    function allocateReward(uint256 _epoch) external onlyDistributorOrOwner {
        EpochInfo memory _epochInfo = epochs[_epoch];
        require(_epochInfo.endTime != 0, "Epoch not ended");
        require(_epochInfo.allocationTime == 0, "Reward allocated");
        uint256 _beforeLLPBalance = LLP.balanceOf(address(this));
        for (uint8 i = 0; i < convertLLPTokens.length;) {
            address _token = convertLLPTokens[i];
            uint256 _amount = IERC20(_token).balanceOf(address(this));
            _convertTokenToLLP(_token, _amount);
            unchecked {
                ++i;
            }
        }
        uint256 _rewardAmount = LLP.balanceOf(address(this)) - _beforeLLPBalance;
        require(_rewardAmount != 0, "Reward = 0");
        _epochInfo.totalReward = _rewardAmount;
        _epochInfo.allocationTime = block.timestamp;
        epochs[_epoch] = _epochInfo;
        emit RewardAllocated(_epoch, _rewardAmount);
    }

    /// @notice convert SELECTED fee tokens to LLP token then allocate to selected epoch. Epoch MUST be ended but not allocated
    function allocateReward(uint256 _epoch, address[] calldata _tokens, uint256[] calldata _amounts)
        external
        onlyDistributorOrOwner
    {
        EpochInfo memory _epochInfo = epochs[_epoch];
        require(_epochInfo.endTime != 0, "Epoch not ended");
        require(_epochInfo.allocationTime == 0, "Reward allocated");
        uint256 _beforeLLPBalance = LLP.balanceOf(address(this));
        for (uint8 i = 0; i < _tokens.length;) {
            uint256 _amount = _amounts[i];
            require(_amount <= IERC20(_tokens[i]).balanceOf(address(this)), "Exceeded balance");
            _convertTokenToLLP(_tokens[i], _amount);
            unchecked {
                ++i;
            }
        }
        uint256 _rewardAmount = LLP.balanceOf(address(this)) - _beforeLLPBalance;
        require(_rewardAmount != 0, "Reward = 0");
        _epochInfo.totalReward = _rewardAmount;
        _epochInfo.allocationTime = block.timestamp;
        epochs[_epoch] = _epochInfo;
        emit RewardAllocated(_epoch, _rewardAmount);
    }

    // =============== RESTRICTED ===============
    function setEnableNextEpoch(bool _enable) external onlyDistributorOrOwner {
        enableNextEpoch = _enable;

        emit EnableNextEpochSet(_enable);
    }

    function setEpochDuration(uint256 _epochDuration) public onlyOwner {
        require(_epochDuration >= MIN_EPOCH_DURATION, "< MIN_EPOCH_DURATION");
        EpochInfo memory _epochInfo = epochs[currentEpoch];
        require(_epochInfo.startTime + _epochDuration >= block.timestamp, "Invalid duration");
        epochDuration = _epochDuration;

        emit EpochDurationSet(epochDuration);
    }

    function setClaimableToken(address _token, bool _allowed) external onlyOwner {
        require(_token != address(stakeToken) && _token != address(LLP) && _token != address(0), "Invalid address");
        if (claimableTokens[_token] != _allowed) {
            claimableTokens[_token] = _allowed;
            emit ClaimableTokenSet(_token, _allowed);
        }
    }

    function setFeeToken(address _token, bool _allowed) external onlyOwner {
        require(_token != address(LLP) && _token != address(stakeToken) && _token != address(0), "Invalid address");
        _setFeeToken(_token, _allowed);
    }

    function pause() external onlyDistributorOrOwner {
        _pause();
    }

    function unpause() external onlyDistributorOrOwner {
        _unpause();
    }

    // =============== INTERNAL FUNCTIONS ===============
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

    // =============== EVENTS ===============
    event EnableNextEpochSet(bool _enable);
    event EpochDurationSet(uint256 _epochDuration);
    event ClaimableTokenSet(address indexed _token, bool _allowed);
    event EpochStarted(uint256 indexed _epoch, uint256 _startTime);
    event EpochEnded(uint256 indexed _epoch, uint256 _endTime);
    event RewardAllocated(uint256 indexed _epoch, uint256 _amount);
    event Staked(address indexed _from, address indexed _to, uint256 _epoch, uint256 _stakedAmount, uint256 _taxAmount);
    event Unstaked(address indexed _from, address indexed _to, uint256 _epoch, uint256 _amount);
    event Claimed(address indexed _from, address indexed _to, uint256 _epoch, uint256 _amount);
    event SingleTokenClaimed(
        address indexed _from,
        address indexed _to,
        uint256 _epoch,
        uint256 _amount,
        address _tokenOut,
        uint256 _amountOut
    );
}

