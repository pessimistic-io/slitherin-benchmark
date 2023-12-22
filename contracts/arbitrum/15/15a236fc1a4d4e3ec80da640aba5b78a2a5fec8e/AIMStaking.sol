// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

/**
 * @title Staking contract with rewards toggling capability
 * @author Bulpara Industries
 * @notice This contract allows users to stake tokens and earn rewards
 */
contract AIMStaking is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public platformToken;

    uint256 public constant FIXED_APY = 60; // 60% fixed APY
    uint256 public constant LOCK_DAYS = 1; // 1 days lockup period
    uint256 public constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;
    uint256 public constant DECIMALS_MULTIPLIER = 1e18;

    uint256 public totalStaked;

    // Enable/Disable reward status
    bool public rewardsEnabled = true;

    // Circuit breaker variables for emergency stop mechanism
    bool public stopped = false;

    struct StakerInfo {
        uint256 stakedAmount;
        uint256 lastClaimTimestamp;
        uint256 lockTimestamp;
    }

    mapping(address => StakerInfo) public stakers;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 rewards);

    modifier stopInEmergency() {
        require(!stopped, "Stopped by owner");
        _;
    }
    modifier onlyInEmergency() {
        require(stopped, "Not in emergency state");
        _;
    }

    /// @notice Constructor to initialize the contract
    /// @param _platformToken The address of the token to be staked
    constructor(IERC20 _platformToken) {
        platformToken = _platformToken;
    }

    /// @notice Allows the contract owner to toggle reward generation status
    function toggleRewards() external onlyOwner {
        rewardsEnabled = !rewardsEnabled;
    }

    /// @notice Allows the contract owner to stop the contract
    function stopContract() external onlyOwner {
        stopped = true;
    }

    /// @notice Allows the contract owner to resume the contract
    function resumeContract() external onlyOwner onlyInEmergency {
        stopped = false;
    }

    /// @notice Allows a user to stake tokens
    /// @param amount The amount of tokens to stake
    function stake(uint256 amount) external stopInEmergency {
        require(amount > 0, "Amount must be greater than 0");
        platformToken.safeTransferFrom(msg.sender, address(this), amount);

        StakerInfo storage staker = stakers[msg.sender];

        // If the user is staking for the first time, set lastClaimTimestamp to now
        if (staker.stakedAmount == 0) {
            staker.lastClaimTimestamp = block.timestamp;
        }

        _updateRewards(msg.sender);

        staker.stakedAmount += amount;
        staker.lockTimestamp = block.timestamp + LOCK_DAYS * 1 days;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    /// @notice Allows a user to unstake tokens
    /// @param amount The amount of tokens to unstake
    function unstake(uint256 amount) external stopInEmergency {
        StakerInfo storage staker = stakers[msg.sender];
        require(amount > 0 && staker.stakedAmount >= amount, "Invalid amount");
        require(
            block.timestamp >= staker.lockTimestamp,
            "Tokens are still locked"
        );

        _updateRewards(msg.sender);

        staker.stakedAmount -= amount;
        totalStaked -= amount;
        platformToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /// @notice Allows a user to claim their rewards
    function claimRewards() external stopInEmergency {
        _updateRewards(msg.sender);
    }

    /// @notice Get the staker's info and pending rewards
    /// @param user The address of the staker
    /// @return stakedAmount The total staked amount of the user
    /// @return pendingRewards The total rewards that the user can claim
    function getStakerInfo(address user)
        external
        view
        returns (uint256 stakedAmount, uint256 pendingRewards)
    {
        StakerInfo storage staker = stakers[user];
        stakedAmount = staker.stakedAmount;
        pendingRewards = _calculatePendingRewards(user);
    }

    /// @notice Get the remaining lock time for a user's tokens
    /// @param user The address of the staker
    /// @return The remaining lock time in seconds
    function getLockTimeLeft(address user) external view returns (uint256) {
        StakerInfo storage staker = stakers[user];
        if (block.timestamp >= staker.lockTimestamp) {
            return 0;
        } else {
            return staker.lockTimestamp - block.timestamp;
        }
    }

    /// @notice Internal function to update user rewards
    /// @param user The address of the staker
    function _updateRewards(address user) internal {
        if (rewardsEnabled) {
            StakerInfo storage staker = stakers[user];
            uint256 pendingRewards = _calculatePendingRewards(user);

            if (pendingRewards > 0) {
                staker.lastClaimTimestamp = block.timestamp;
                platformToken.safeTransfer(user, pendingRewards);
                emit RewardsClaimed(user, pendingRewards);
            } else {
                staker.lastClaimTimestamp = block.timestamp;
            }
        }
    }

    /// @notice Internal function to calculate pending rewards for a user
    /// @param user The address of the staker
    /// @return The amount of pending rewards for the user
    function _calculatePendingRewards(address user)
        internal
        view
        returns (uint256)
    {
        if (rewardsEnabled) {
            StakerInfo storage staker = stakers[user];
            uint256 timeSinceLastClaim = block.timestamp -
                staker.lastClaimTimestamp;
            uint256 rewardRate = (staker.stakedAmount *
                FIXED_APY *
                timeSinceLastClaim) / (SECONDS_IN_A_YEAR * 100);
            return rewardRate;
        } else {
            return 0;
        }
    }
}

