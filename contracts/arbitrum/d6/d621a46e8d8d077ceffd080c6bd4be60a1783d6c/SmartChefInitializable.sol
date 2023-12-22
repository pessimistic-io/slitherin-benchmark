// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IPancakeProfile} from "./IPancakeProfile.sol";

contract SmartChefInitializable is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    // The address of the smart chef factory
    address public immutable SMART_CHEF_FACTORY;

    // Whether a limit is set for users
    bool public userLimit;

    // Whether it is initialized
    bool public isInitialized;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The block timestamp when CAKE mining ends
    uint256 public endTimestamp;

    // The block timestamp when CAKE mining starts
    uint256 public startTimestamp;

    // The block timestamp of the last pool update
    uint256 public lastRewardTimestamp;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // Seconds available for user limit (after start timestamp)
    uint256 public numberSecondsForUserLimit;

    // Pancake profile address
    address public immutable pancakeProfile;

    // Pancake Profile is requested
    bool public pancakeProfileIsRequested;

    // Pancake Profile points threshold
    uint256 public pancakeProfileThresholdPoints;

    // CAKE tokens created per second
    uint256 public rewardPerSecond;

    // The precision factor
    uint256 public PRECISION_FACTOR;

    // The reward token
    IERC20Metadata public rewardToken;

    // The staked token
    IERC20Metadata public stakedToken;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt;
    }

    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndTimestamp(uint256 startTimestamp, uint256 endTimestamp);
    event NewRewardPerSecond(uint256 rewardPerSecond);
    event NewPoolLimit(uint256 poolLimitPerUser);
    event RewardsStop(uint256 blockNumber);
    event TokenRecovery(address indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event UpdateProfileAndThresholdPointsRequirement(bool isProfileRequested, uint256 thresholdPoints);

    /**
     * @notice Constructor
     * @param _pancakeProfile: Pancake Profile address
     * @param _pancakeProfileIsRequested: Pancake Profile is requested
     * @param _pancakeProfileThresholdPoints: Pancake Profile need threshold points
     */
    constructor(
        address _pancakeProfile,
        bool _pancakeProfileIsRequested,
        uint256 _pancakeProfileThresholdPoints
    ) {
        SMART_CHEF_FACTORY = msg.sender;

        pancakeProfile = _pancakeProfile; // It can be empty on Other chain

        if (_pancakeProfile != address(0)) {
            IPancakeProfile(_pancakeProfile).getTeamProfile(1);

            // if pancakeProfile is requested
            pancakeProfileIsRequested = _pancakeProfileIsRequested;

            // pancakeProfile threshold points when profile & points are requested
            pancakeProfileThresholdPoints = _pancakeProfileThresholdPoints;
        } else {
            pancakeProfileIsRequested = false;
            pancakeProfileThresholdPoints = 0;
        }
    }

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerSecond: reward per second (in rewardToken)
     * @param _startTimestamp: start block timestamp
     * @param _endTimestamp: end block timestamp
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     * @param _numberSecondsForUserLimit: seconds available for user limit (after start timestamp)
     * @param _admin: admin address with ownership
     */
    function initialize(
        IERC20Metadata _stakedToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardPerSecond,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        uint256 _poolLimitPerUser,
        uint256 _numberSecondsForUserLimit,
        address _admin
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == SMART_CHEF_FACTORY, "Not factory");
        require(_startTimestamp < _endTimestamp, "New startTimestamp must be lower than new endTimestamp");
        require(block.timestamp < _startTimestamp, "New startTimestamp must be higher than current block timestamp");

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerSecond = _rewardPerSecond;
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;

        if (_poolLimitPerUser > 0) {
            userLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
            numberSecondsForUserLimit = _numberSecondsForUserLimit;
        }

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30) - decimalsRewardToken));
        require(
            (PRECISION_FACTOR * rewardPerSecond) / (10**decimalsRewardToken) >= 100_000_000,
            "rewardPerSecond must be larger"
        );

        // Set the lastRewardBlock as the startTimestamp
        lastRewardTimestamp = startTimestamp;

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        if (pancakeProfile != address(0)) {
            // Checks whether the user has an active profile
            require(
                (!pancakeProfileIsRequested && pancakeProfileThresholdPoints == 0) ||
                    IPancakeProfile(pancakeProfile).getUserStatus(msg.sender),
                "Deposit: Must have an active profile"
            );

            uint256 numberUserPoints = 0;

            if (pancakeProfileThresholdPoints > 0) {
                require(pancakeProfile != address(0), "Deposit: PancakeProfile is not exist");
                (, numberUserPoints, , , , ) = IPancakeProfile(pancakeProfile).getUserProfile(msg.sender);
            }

            require(
                pancakeProfileThresholdPoints == 0 || numberUserPoints >= pancakeProfileThresholdPoints,
                "Deposit: User is not get enough user points"
            );
        }

        userLimit = hasUserLimit();

        require(!userLimit || ((_amount + user.amount) <= poolLimitPerUser), "Deposit: Amount above limit");

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
            if (pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }

        if (_amount > 0) {
            user.amount = user.amount + _amount;
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        uint256 pending = (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            stakedToken.safeTransfer(address(msg.sender), _amount);
        }

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;

        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        if (amountToTransfer > 0) {
            stakedToken.safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice Allows the owner to recover tokens sent to the contract by mistake
     * @param _token: token address
     * @dev Callable by owner
     */
    function recoverToken(address _token) external onlyOwner {
        require(_token != address(stakedToken), "Operations: Cannot recover staked token");
        require(_token != address(rewardToken), "Operations: Cannot recover reward token");

        uint256 balance = IERC20Metadata(_token).balanceOf(address(this));
        require(balance != 0, "Operations: Cannot recover zero balance");

        IERC20Metadata(_token).safeTransfer(address(msg.sender), balance);

        emit TokenRecovery(_token, balance);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        endTimestamp = block.timestamp;
        emit RewardsStop(endTimestamp);
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _userLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(bool _userLimit, uint256 _poolLimitPerUser) external onlyOwner {
        require(userLimit, "Must be set");
        if (_userLimit) {
            require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            userLimit = _userLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerSecond: the reward per second
     */
    function updateRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        require(block.timestamp < startTimestamp, "Pool has started");
        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(
            (PRECISION_FACTOR * _rewardPerSecond) / (10**decimalsRewardToken) >= 100_000_000,
            "rewardPerSecond must be larger"
        );
        rewardPerSecond = _rewardPerSecond;
        emit NewRewardPerSecond(_rewardPerSecond);
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @dev This function is only callable by owner.
     * @param _startTimestamp: the new start block timestamp
     * @param _endTimestamp: the new end block timestamp
     */
    function updateStartAndEndTimestamp(uint256 _startTimestamp, uint256 _endTimestamp) external onlyOwner {
        require(block.timestamp < startTimestamp, "Pool has started");
        require(_startTimestamp < _endTimestamp, "New startTimestamp must be lower than new endTimestamp");
        require(block.timestamp < _startTimestamp, "New startTimestamp must be higher than current block timestamp");

        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;

        emit NewStartAndEndTimestamp(_startTimestamp, _endTimestamp);
    }

    /**
     * @notice It allows the admin to update profile and thresholdPoints' requirement.
     * @dev This function is only callable by owner.
     * @param _isRequested: the profile is requested
     * @param _thresholdPoints: the threshold points
     */
    function updateProfileAndThresholdPointsRequirement(bool _isRequested, uint256 _thresholdPoints)
        external
        onlyOwner
    {
        require(pancakeProfile != address(0), "Pancake profile address is null");
        require(_thresholdPoints >= 0, "Threshold points need to exceed 0");
        pancakeProfileIsRequested = _isRequested;
        pancakeProfileThresholdPoints = _thresholdPoints;
        emit UpdateProfileAndThresholdPointsRequirement(_isRequested, _thresholdPoints);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        if (block.timestamp > lastRewardTimestamp && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 cakeReward = multiplier * rewardPerSecond;
            uint256 adjustedTokenPerShare = accTokenPerShare + (cakeReward * PRECISION_FACTOR) / stakedTokenSupply;
            return (user.amount * adjustedTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        } else {
            return (user.amount * accTokenPerShare) / PRECISION_FACTOR - user.rewardDebt;
        }
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardTimestamp, block.timestamp);
        uint256 cakeReward = multiplier * rewardPerSecond;
        accTokenPerShare = accTokenPerShare + (cakeReward * PRECISION_FACTOR) / stakedTokenSupply;
        lastRewardTimestamp = block.timestamp;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= endTimestamp) {
            return _to - _from;
        } else if (_from >= endTimestamp) {
            return 0;
        } else {
            return endTimestamp - _from;
        }
    }

    /*
     * @notice Return user limit is set or zero.
     */
    function hasUserLimit() public view returns (bool) {
        if (!userLimit || (block.timestamp >= (startTimestamp + numberSecondsForUserLimit))) {
            return false;
        }

        return true;
    }
}

