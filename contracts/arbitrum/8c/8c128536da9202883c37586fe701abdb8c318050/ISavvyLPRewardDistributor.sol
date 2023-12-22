// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title Savvy LP Reward Distributor
/// @author Savvy DeFi
/// @dev manage rewards for Savvy LPers.

interface ISavvyLPRewardDistributor {
  struct AccountRewards {
    /// @notice The user earning rewards.
    address user;
    /// @notice The lp token the rewards are associated with.
    address lpToken;
    /// @notice The rewards the user can claim from this source.
    uint256 claimableRewards;
    /// @notice The rewards that have already been claimed.
    uint256 claimedRewards;
    /// @notice The last time this source was claimed.
    uint256 lastClaimed;
  }

  struct UpdatedRewards {
    /// @notice The user to update the rewards for.
    address user;
    /// @notice The lp token to update the rewards for.
    address lpToken;
    /// @notice The new rewards that will be added to the user's existing claimable balance.
    uint256 newRewards;
  }

  struct SourceRewards {
    /// @notice The lp token to get the rewards for.
    address lpToken;
    /// @notice The total rewards for the lp token.
    uint256 totalRewards;
    /// @notice Whether the lp token is a valid source of rewards.
    bool enabled;
  }

  /// @notice The last timestamp the rewards were updated.
  /// @return lastUpdatedTimestamp The last timestamp the rewards were updated.
  function lastUpdated() external view returns (uint256 lastUpdatedTimestamp);

  /// @notice Gets all the lp sources for the rewarder.
  /// @return lpSources_ The lp sources.
  function lpSources()
    external
    view
    returns (SourceRewards[] memory lpSources_);

  /// @notice sets whether an LP token is a valid source of rewards.
  /// @param _lpTokens The lp tokens to set the validity of.
  /// @param _enabled Whether the lp token is a valid source of rewards.
  function setLpSources(address[] calldata _lpTokens, bool _enabled) external;

  /// @notice Record new rewards for users.
  /// @dev will revert if the caller is not a keeper.
  /// @param _updatedRewards The updated rewards to record. This will add
  /// on to the existing rewards for the user and the source.
  function recordNewRewards(
    UpdatedRewards[] calldata _updatedRewards,
    uint256 timestamp
  ) external;

  /// @notice Gets the total claimable SVY rewards across all LP sources for the user.
  /// @param _user The user to get the total claimable rewards for.
  /// @return totalClaimableRewards The total claimable SVY rewards for the user.
  /// @return claimableRewardsBySource The claimable SVY rewards for the user by source.
  function getTotalClaimableRewards(
    address _user
  )
    external
    view
    returns (
      uint256 totalClaimableRewards,
      AccountRewards[] memory claimableRewardsBySource
    );

  /// @notice Gets the total claimable SVY rewards across all LP sources for the user.
  /// @param _user The user to get the total claimable rewards for.
  /// @param _lpTokens The lp tokens to get the total claimable rewards for.
  /// @return totalClaimableRewards The total claimable SVY rewards for the user.
  /// @return claimableRewardsBySource The claimable SVY rewards for the user by source.
  function getClaimableRewards(
    address _user,
    address[] calldata _lpTokens
  )
    external
    view
    returns (
      uint256 totalClaimableRewards,
      AccountRewards[] memory claimableRewardsBySource
    );

  /// @notice Gets the total claimable SVY rewards across all LP sources for the user.
  /// @dev This is equivalent to calling
  /// ```solidity
  /// claimRewards(_user, lpSources())
  /// ```
  /// @param _user The user to get the total claimable rewards for.
  /// @return rewardsClaimed The total claimed SVY rewards for the user.
  /// @return rewardsClaimedBySource The claimed SVY rewards for the user by source.
  function claimAllRewards(
    address _user
  )
    external
    returns (
      uint256 rewardsClaimed,
      AccountRewards[] memory rewardsClaimedBySource
    );

  /// @notice Gets the total claimable SVY rewards across all LP sources for the user.
  /// @param _user The user to get the total claimable rewards for.
  /// @param _lpTokens The lp sources to claim from.
  /// @return rewardsClaimed The total claimed SVY rewards for the user.
  /// @return rewardsClaimedBySource The claimed SVY rewards for the user by source.
  function claimRewards(
    address _user,
    address[] calldata _lpTokens
  )
    external
    returns (
      uint256 rewardsClaimed,
      AccountRewards[] memory rewardsClaimedBySource
    );

  /// @notice Stake all the claimable SVY rewards on behalf of the user.
  /// The user can then withdraw the staked rewards at any time using `veSVY`.
  /// @dev This is equivalent to calling
  /// ```solidity
  /// stakeRewards(_user, lpSources())
  /// ```
  /// @param _user The user to stake rewards on behalf of.
  /// @return rewardsStaked The total staked SVY rewards for the user.
  /// @return rewardsStakedBySource The staked SVY rewards for the user by source.
  function stakeAllRewards(
    address _user
  )
    external
    returns (
      uint256 rewardsStaked,
      AccountRewards[] memory rewardsStakedBySource
    );

  /// @notice Stake specific claimable SVY rewards based on source on behalf of the user.
  /// The user can then withdraw the staked rewards at any time using `veSVY`.
  /// @param _user The user to stake rewards on behalf of.
  /// @param _lpTokens The lp sources to stake rewards from.
  /// @return rewardsStaked The total staked SVY rewards for the user.
  /// @return rewardsStakedBySource The staked SVY rewards for the user by source.
  function stakeRewards(
    address _user,
    address[] calldata _lpTokens
  )
    external
    returns (
      uint256 rewardsStaked,
      AccountRewards[] memory rewardsStakedBySource
    );

  /// @notice Claim and stake specific sources for a user.
  /// Staked rewards can be withdrawn at any time using `veSVY`.
  /// @param _user The user to stake rewards on behalf of.
  /// @param _lpSourceToClaim The lp sources to claim rewards from.
  /// @param _lpSourceToStake The lp sources to stake rewards from.
  /// @return rewardsClaimed The total claimed SVY rewards for the user.
  /// @return rewardsClaimedBySource The claimed SVY rewards for the user by source.
  /// @return rewardsStaked The total staked SVY rewards for the user.
  /// @return rewardsStakedBySource The staked SVY rewards for the user by source.
  function claimAndStakeRewards(
    address _user,
    address[] calldata _lpSourceToClaim,
    address[] calldata _lpSourceToStake
  )
    external
    returns (
      uint256 rewardsClaimed,
      AccountRewards[] memory rewardsClaimedBySource,
      uint256 rewardsStaked,
      AccountRewards[] memory rewardsStakedBySource
    );

  event LpSourceUpdated(address indexed lpToken, bool enabled);

  event RewardsRecorded(
    address indexed user,
    address indexed lpToken,
    uint256 newRewards,
    uint256 totalRewards
  );

  event RewardsClaimed(
    address indexed user,
    address indexed lpToken,
    uint256 claimedRewards,
    bool indexed isClaimStaked
  );
}

