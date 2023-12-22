// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IUnlimitedStaking
 * @notice Interface for the Unlimited Staking contract.
 * The UnlimitedStaking contract is a smart contract that allows users to stake their 
 * UWU tokens in order to earn rewards. The contract consists of several parts, including 
 * epochs, rewards, and user information. Epochs represent different staking options, each
 * lock period its unique multiplier. Users can deposit their UWU tokens
 * into a epoch and receive boosted shares, which are used to calculate their share of the
 * epoch's rewards.
 */
interface IUnlimitedStaking {
    /// @notice Info of each UnlimitedStaking epoch.
    /// `accRewardPerShare` The accumulated static reward per share (boosted amount) in the epoch.
    /// `accDynamicRewardPerShare` The accumulated dynamic reward (instantly calculated by balanceOf) per share (boosted amount) in the epoch.
    /// `endTime` The timestamp when the epoch ends.
    /// `totalCurrentBoostedShare` The total boosted share (staking amount multiplied by boost multiplier) for the current epoch.
    /// `totalNextBoostedShare` The total boosted share (staking amount multiplied by boost multiplier) for the next epoch.
    /// `totalNextResetBoostedShare` The total amount of boosted share to be reset in the next epoch.
    /// `totalAmountStaked` The total amount staked in the current epoch.
    /// `isUpdated` A flag indicating whether the epoch has been updated or not.
    ///
    /// There are two types of rewards: static rewards and dynamic rewards.
    /// Static rewards are distributed based on a predetermined rate, while dynamic 
    /// rewards are distributed based on the amount of UWU tokens held in a 
    /// separate dynamic rewards wallet.
    ///
    ///   Whenever a user deposits or withdraws UWU tokens to a pool. Here's what happens:
    ///   1. The pool's `accRewardPerShare`, `accDynamicRewardPerShare` gets updated.
    ///   1. The reward's `lastDynamicRewardBalance` gets updated.
    ///   3. User's `amount` gets updated. Reward's `totalNextBoostedShare` gets updated.
    struct EpochInfo {
        uint256 accRewardPerShare; // Accumulated reward per share
        uint256 accDynamicRewardPerShare; // Accumulated dynamic reward per share
        uint256 endTime; // End time of the epoch
        uint256 totalCurrentBoostedShare; // Total boosted share in the current epoch
        uint256 totalNextBoostedShare; // Total boosted share in the next epoch
        uint256 totalNextResetBoostedShare; // Total boosted share in the next reset epoch
        uint256 totalAmountStaked; // Total amount staked in the epoch
        bool isUpdated; // Whether the epoch has been updated
    }

    /// @notice Struct representing user information.
    struct UserInfo {
        uint256 amount; // Amount staked
        uint256 multiplier; // Multiplier of the stake
        uint256 resetEpoch; // Epoch at which the stake multiplier will reset
        uint256 lockPeriod; // Lock period of the stake
        uint256 depositDate; // Date when the stake was deposited
        uint256 withdrawEpoch; // Epoch at which the stake was requested to withdraw
        uint256 lastClaimEpoch; // Epoch at which the stake was last claimed
        uint256 compoundEpoch; // Epoch at which the stake was last compounded
        uint256 lastCompoundDelta; // Amount of tokens compounded since the last compound which will be activate in next epoch
    }

    /// @notice Struct representing reward information.
    struct RewardInfo {
        uint256 totalAmountStatic; // Total amount of static reward
        uint256 startEpoch; // Start epoch of the reward
        uint256 endEpoch; // End epoch of the reward
    }

    /// @notice Struct representing dynamic reward information.
    struct DynamicRewardInfo {
        uint256 totalRewardDept; // Total reward debt
        uint256 lastBalance; // Last balance of the reward pool
        uint256 lastBalanceUpdateTime; // Time when the last balance was updated
        uint256 startEpoch; // Start epoch of the reward
        uint256 endEpoch; // End epoch of the reward
    }

    event EpochUpdated(uint256 indexed epochNumber, uint256 accRewardPerShare);
    event EpochChanged(uint256 indexed epochNumber, uint256 totalCurrentBoostedShare, uint256 totalAmountStaked);
    event StaticRewardAdded(uint256 amount, uint256 startEpoch, uint256 endEpoch);
    event DynamicRewardAdded(uint256 startEpoch, uint256 endEpoch);
    event LockPeriodAdded(uint256 lockPeriod, uint256 multiplier);
    event LockPeriodEdited(uint256 lockPeriod, uint256 multiplier);
    event LockPeriodRemoved(uint256 lockPeriod);
    event Deposited(uint256 indexed tokenId, uint256 amount, uint256 lockPeriod, uint256 multiplier, uint256 epochNumber);
    event Claimed(uint256 indexed tokenId, address indexed user, uint256 amount);
    event WithdrawalRequested(uint256 indexed tokenId, address indexed user, uint256 epochNumber);
    event Withdraw(uint256 indexed tokenId, address indexed user, uint256 epochNumber);
    event Compounded(uint256 indexed tokenId, uint256 amount, uint256 epochNumber);

    /**
     * @notice Add static reward to the contract.
     * @param _amount Amount of tokens to add.
     * @param _startEpoch Start epoch of the reward.
     * @param _endEpoch End epoch of the reward.
     */
    function addStaticReward(
        uint256 _amount,
        uint256 _startEpoch,
        uint256 _endEpoch
    ) external;

    /**
     * @notice Add dynamic reward to the contract.
     * @param _startEpoch Start epoch of the reward.
     * @param _endEpoch End epoch of the reward.
     */
    function addDynamicReward(uint256 _startEpoch, uint256 _endEpoch) external;

    /**
     * @notice Add a new lock period.
     * @param _lockPeriod Lock period of the stake.
     * @param _multiplier Multiplier of the stake.
     */
    function addLockPeriod(uint256 _lockPeriod, uint256 _multiplier) external;

    /**
     * @notice Edit an existing lock period.
     * @param _lockPeriod New lock period of the stake.
     * @param _multiplier New multiplier of the stake.
     */
    function editLockPeriod(uint256 _lockPeriod, uint256 _multiplier) external;

    /**
     * @notice Remove an existing lock period.
     * @param _lockPeriod Lock period of the stake to remove.
     */
    function removeLockPeriod(uint256 _lockPeriod) external;

    /**
     * @dev Updates the information related to the current epoch.
     *
     * This function performs the following actions:
     * - If the current epoch has not been updated, it updates the accumulated static reward per share.
     * - Updates the accumulated dynamic reward per share.
     * - Sets the 'isUpdated' flag for the current epoch to true.
     * - If the current epoch has ended, it initializes the next epoch with the appropriate values.
     *
     * @return currentEpoch - The updated EpochInfo struct for the current epoch.
    */
    function updateEpoch() external returns (EpochInfo memory);

    /**
     * @notice Deposit tokens and create a new stake.
     *
     * This function performs the following actions:
     * - Updates the current epoch information.
     * - Transfers the tokens from the user to the contract.
     * - Creates a new UserInfo struct for the user's deposit.
     * - Mints a new NFT representing the stake.
     * - Updates the total boosted share for the epoch.
     *   it sets a reset epoch for the user's stake and updates the total next reset boosted share.
     *
     * @param _amount Amount of tokens to deposit.
     * @param _lockPeriod Lock period for the stake in epochs.
    */
    function deposit(uint256 _amount, uint256 _lockPeriod) external;

    /**
     * @notice Deposit tokens with a permit and create a new stake.
     * @param _amount Amount of tokens to deposit.
     * @param _lockPeriod Lock period for the stake in epochs.
     * @param _depositOwner Owner of the deposit.
     * @param _value Value of the permit.
     * @param _deadline Deadline for the permit.
     * @param _v Recovery byte of the permit signature.
     * @param _r First 32 bytes of the permit signature.
     * @param _s Second 32 bytes of the permit signature.
     */
    function depositPermit(
        uint256 _amount,
        uint256 _lockPeriod,
        address _depositOwner,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    /**
     * @notice Claim the pending rewards for a specific stake represented by the token ID.
     *
     * This function performs the following actions:
     * - Updates the current epoch information.
     * - Verifies that the caller is the owner, has been approved, or has been granted approval for all.
     * - Ensures that the last claimed epoch is less than the current epoch.
     * - Settles the pending rewards for the stake.
     * - Updates the user's last claimed epoch to the current epoch.
     *
     * @param _tokenId The token ID representing the stake for which to claim rewards.
    */
    function claim(uint256 _tokenId) external;

    /**
     * @notice Claim rewards for all provided token IDs.
     * @param _tokenIds Array of token IDs to claim rewards for.
     */
    function claimAll(uint256[] memory _tokenIds) external;

    /**
    * @notice Request the withdrawal of a stake represented by the token ID.
     *
     * This function performs the following actions:
     * - Verifies that the caller is the owner, has been approved, or has been granted approval for all.
     * - Updates the current epoch information.
     * - Ensures that the current epoch number is greater than or equal to the user's last claimed epoch.
     * - Ensures that the current time is greater than unlock time.
     * - Sets the withdraw epoch for the user to the next epoch.
     * - Decreases the total boosted shares and total staked amount for the current epoch.
     *
     * @param _tokenId The token ID representing the stake for which to request a withdrawal.
    */
    function withdrawRequest(uint256 _tokenId) external;

    /**
     * @notice Withdraw tokens for a specific token ID.
     * @param _tokenId Token ID to withdraw tokens for.
     */
    function withdraw(uint256 _tokenId) external;

    /**
     * @notice Compound rewards for a specific token ID.
     * @param _tokenId Token ID to compound rewards for.
     */
    function compound(uint256 _tokenId) external;

    /**
     * @notice Compound rewards for all provided token IDs.
     * @param _tokenIds Array of token IDs to compound rewards for.
     */
    function compoundAll(uint256[] memory _tokenIds) external;

    /**
     * @notice Get the total number of static rewards.
     * @return rewards Total number of static rewards.
     */
    function rewardLength() external view returns (uint256 rewards);

    /**
     * @notice Get the static reward amount per epoch for a specific reward ID.
     * @param _uwuRewardId Reward ID to get the static reward amount for.
     * @return amount Static reward amount per epoch.
     */
    function uwuStaticPerBlock(
        uint256 _uwuRewardId
    ) external view returns (uint256 amount);

    /**
     * @notice Get the user's pending rewards for a specific token ID.
     * @param _tokenId Token ID to get pending rewards for.
     * @return amount Pending rewards amount.
     */
    function userPendingRewards(
        uint256 _tokenId
    ) external view returns (uint256 amount);

    /**
     * @notice Get the user's reward for a specific token ID and epoch.
     * @param _tokenId Token ID to get the reward for.
     * @param _epoch Epoch to get the reward for.
     * @return Reward amount for the specified token ID and epoch.
     */
    function getUserRewardForEpoch(
        uint256 _tokenId,
        uint256 _epoch
    ) external view returns (uint256);

    /**
     * @notice Get the user's staking information for a specific token ID.
     * @param _tokenId Token ID to get the user's staking information for.
     * @return userInfo Struct containing the user's staking information.
     */
    function getUserInfo(
        uint256 _tokenId
    ) external view returns (UserInfo memory);

    /**
     * @notice Get the user's multiplier for a specific token ID.
     * @param _tokenId Token ID to get the user's multiplier for.
     * @return multiplier The multiplier for the specified token ID.
     */
    function getUserMultiplier(
        uint256 _tokenId
    ) external view returns (uint256 multiplier);

    /**
     * @notice Get the information of the current epoch.
     * @return epochInfo Struct containing the current epoch's information.
     */
    function getCurrentEpochInfo() external view returns (EpochInfo memory);

    /**
     * @notice Get current epoch number.
     * @return currentEpochNumber Number of the current epoch.
     */
    function getCurrentEpochNumber() external view returns (uint256);

    /**
     * @notice Get the reward information for a specific reward ID.
     * @param _rewardId Reward ID to get the reward information for.
     * @return rewardInfo Struct containing the reward information for the specified reward ID.
     */
    function getRewardInfo(
        uint256 _rewardId
    ) external view returns (RewardInfo memory);
}

