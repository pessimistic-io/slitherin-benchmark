// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./TokenUtils.sol";
import "./ISavvyLPRewardDistributor.sol";
import "./IVeSvy.sol";
import "./ErrorMessages.sol";

/// @title SavvyLPRewardDistributor
contract SavvyLPRewardDistributor is
  ISavvyLPRewardDistributor,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable
{
  /// @notice The identifier of the role which maintains other roles.
  bytes32 public constant ADMIN = keccak256("ADMIN");

  /// @notice The identifier of the keeper role.
  bytes32 public constant KEEPER = keccak256("KEEPER");

  /// @notice The storage pointer of last updated reward time
  uint256 _lastUpdated;

  /// @notice The array of LP tokens
  address[] public lpTokenList;

  /// @notice The pointer to VeSvy smart contract
  IVeSvy public veSVY;

  /// @notice The smart contract address of SVY token
  address public SVY;

  /// @notice The mapping of lpToken address to SourceRewards.
  mapping(address => SourceRewards) sourceRewards;

  /// @notice The mapping of the lpToken to user to AccountRewards.
  ///     lp source => user => AccountRewards
  mapping(address => mapping(address => AccountRewards)) _accountRewards;

  /// @dev check if user is _msgSender()
  modifier isMsgSender(address _user) {
    require(_user == _msgSender() || _user == tx.origin, "Invalid Caller");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address admin,
    address keeper,
    address svy,
    address veSvy
  ) external initializer {
    __ReentrancyGuard_init();

    _grantRole(ADMIN, admin);
    _grantRole(KEEPER, keeper);
    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    _setRoleAdmin(KEEPER, DEFAULT_ADMIN_ROLE);
    _setRoleAdmin(ADMIN, DEFAULT_ADMIN_ROLE);

    SVY = svy;
    veSVY = IVeSvy(veSvy);
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function lpSources()
    external
    view
    returns (SourceRewards[] memory lpSources_)
  {
    uint256 length = lpTokenList.length;
    address[] memory lpTokens = new address[](length);
    lpTokens = lpTokenList;
    lpSources_ = new SourceRewards[](length);

    for (uint256 i; i < length; ++i) {
      lpSources_[i] = sourceRewards[lpTokens[i]];
    }
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function setLpSources(
    address[] calldata _lpTokens,
    bool _enabled
  ) external onlyRole(ADMIN) {
    uint256 length = _lpTokens.length;
    address lpToken;

    SourceRewards memory sourceReward;

    for (uint256 i; i < length; ++i) {
      lpToken = _lpTokens[i];

      if (lpToken == address(0)) {
        revert IllegalArgumentWithReason("Zero LP token address");
      }
      sourceReward = sourceRewards[lpToken];

      if (sourceReward.lpToken == address(0)) {
        lpTokenList.push(lpToken);
        sourceRewards[lpToken] = SourceRewards(lpToken, 0, _enabled);
      } else {
        sourceRewards[lpToken].enabled = _enabled;
      }
      emit LpSourceUpdated(lpToken, _enabled);
    }
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function recordNewRewards(
    UpdatedRewards[] calldata _updatedRewards,
    uint256 timestamp
  ) external onlyRole(KEEPER) nonReentrant {
    uint256 totalAmount;
    uint256 rewardsLength = _updatedRewards.length;

    UpdatedRewards memory updatedRewards;
    AccountRewards storage accountRewards;

    for (uint256 i; i < rewardsLength; ++i) {
      updatedRewards = _updatedRewards[i];

      if (!sourceRewards[updatedRewards.lpToken].enabled) {
        revert IllegalArgumentWithReason("Disabled source included");
      }

      accountRewards = _accountRewards[updatedRewards.lpToken][
        updatedRewards.user
      ];

      if (accountRewards.user == address(0)) {
        accountRewards.user = updatedRewards.user;
        accountRewards.lpToken = updatedRewards.lpToken;
      }

      accountRewards.claimableRewards += updatedRewards.newRewards;
      totalAmount += updatedRewards.newRewards;

      emit RewardsRecorded(
        updatedRewards.user,
        updatedRewards.lpToken,
        updatedRewards.newRewards,
        _accountRewards[updatedRewards.lpToken][updatedRewards.user]
          .claimableRewards
      );
    }

    TokenUtils.safeTransferFrom(SVY, _msgSender(), address(this), totalAmount);

    if (timestamp == 0) _lastUpdated = block.timestamp;
    else _lastUpdated = timestamp;
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function lastUpdated() external view returns (uint256 lastUpdatedTimestamp) {
    lastUpdatedTimestamp = _lastUpdated;
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function getClaimableRewards(
    address _user,
    address[] calldata _lpTokens
  )
    external
    view
    returns (
      uint256 totalClaimableRewards,
      AccountRewards[] memory claimableRewardsBySource
    )
  {
    return _getClaimableRewards(_user, _lpTokens);
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function getTotalClaimableRewards(
    address _user
  )
    external
    view
    returns (
      uint256 totalClaimableRewards,
      AccountRewards[] memory claimableRewardsBySource
    )
  {
    return _getClaimableRewards(_user, lpTokenList);
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function claimRewards(
    address _user,
    address[] calldata _lpTokens
  )
    external
    isMsgSender(_user)
    returns (
      uint256 rewardsClaimed,
      AccountRewards[] memory claimedRewardsBySource
    )
  {
    return _claim(_user, _lpTokens);
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function claimAllRewards(
    address _user
  )
    external
    isMsgSender(_user)
    returns (
      uint256 rewardsClaimed,
      AccountRewards[] memory claimedRewardsBySource
    )
  {
    return _claim(_user, lpTokenList);
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function stakeRewards(
    address _user,
    address[] calldata _lpTokens
  )
    external
    isMsgSender(_user)
    returns (
      uint256 rewardsStaked,
      AccountRewards[] memory rewardsStakedBySource
    )
  {
    return _stake(_user, _lpTokens);
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function stakeAllRewards(
    address _user
  )
    external
    isMsgSender(_user)
    returns (
      uint256 rewardsStaked,
      AccountRewards[] memory rewardsStakedBySource
    )
  {
    return _stake(_user, lpTokenList);
  }

  /// @inheritdoc ISavvyLPRewardDistributor
  function claimAndStakeRewards(
    address _user,
    address[] calldata _lpSourceToClaim,
    address[] calldata _lpSourceToStake
  )
    external
    isMsgSender(_user)
    returns (
      uint256 rewardsClaimed,
      AccountRewards[] memory rewardsClaimedBySource,
      uint256 rewardsStaked,
      AccountRewards[] memory rewardsStakedBySource
    )
  {
    // claimable rewards to claim
    (rewardsClaimed, rewardsClaimedBySource) = _claim(_user, _lpSourceToClaim);

    // stake rewards to stake
    (rewardsStaked, rewardsStakedBySource) = _stake(_user, _lpSourceToStake);
  }

  function _getClaimableReward(
    address _user,
    address _lpToken
  ) private view returns (AccountRewards memory claimableReward) {
    claimableReward = _accountRewards[_lpToken][_user];
    if (claimableReward.user == address(0)) {
      claimableReward.user = _user;
      claimableReward.lpToken = _lpToken;
    }
  }

  function _getClaimableRewards(
    address _user,
    address[] memory _lpTokens
  )
    private
    view
    returns (
      uint256 totalClaimableRewards,
      AccountRewards[] memory claimableRewards
    )
  {
    uint256 length = _lpTokens.length;
    claimableRewards = new AccountRewards[](length);

    for (uint256 i; i < length; ++i) {
      claimableRewards[i] = _getClaimableReward(_user, _lpTokens[i]);
      totalClaimableRewards += claimableRewards[i].claimableRewards;
    }
  }

  /**
   * @dev This will update the claimed and claimable trackers for the account.
   * **NOTE** This will not transfer SVY so the caller will need to send or stake the SVY on behalf of the user.
   **/
  function _updateClaimableRewards(
    address _user,
    address[] memory _lpTokens,
    bool willClaimBeStaked
  )
    private
    returns (uint256 rewards, AccountRewards[] memory claimedRewardsBySource)
  {
    claimedRewardsBySource = new AccountRewards[](_lpTokens.length);

    uint256 amount;
    address lpToken;
    uint256 length = _lpTokens.length;
    AccountRewards storage accountRewards_;

    for (uint256 i; i < length; ++i) {
      lpToken = _lpTokens[i];
      accountRewards_ = _accountRewards[lpToken][_user];
      require(
        accountRewards_.lastClaimed < block.timestamp,
        "Cannot claim rewards for LP token twice."
      );
      amount = (_getClaimableReward(_user, lpToken)).claimableRewards;
      rewards += amount;

      if (amount > 0) {
        accountRewards_.lastClaimed = block.timestamp;

        accountRewards_.claimedRewards += amount;
        accountRewards_.claimableRewards -= amount;

        emit RewardsClaimed(_user, lpToken, amount, willClaimBeStaked);
      }
    }
  }

  function _claim(
    address _user,
    address[] memory _lpTokens
  )
    private
    returns (
      uint256 rewardsClaimed,
      AccountRewards[] memory claimedRewardsBySource
    )
  {
    (rewardsClaimed, claimedRewardsBySource) = _updateClaimableRewards(
      _user,
      _lpTokens,
      false
    );

    if (rewardsClaimed == 0) {
      revert UnsupportedOperationWithReason("Nothing available to claim");
    }
    TokenUtils.safeTransfer(SVY, _user, rewardsClaimed);
  }

  function _stake(
    address _user,
    address[] memory _lpTokens
  )
    private
    returns (
      uint256 rewardsStaked,
      AccountRewards[] memory rewardsStakedByAccount
    )
  {
    (rewardsStaked, rewardsStakedByAccount) = _updateClaimableRewards(
      _user,
      _lpTokens,
      true
    );

    if (rewardsStaked == 0) {
      revert UnsupportedOperationWithReason("Nothing available to stake");
    }

    TokenUtils.safeApprove(SVY, address(veSVY), rewardsStaked);
    veSVY.stakeFor(_user, rewardsStaked);
  }

  uint256[100] private __gap;
}

