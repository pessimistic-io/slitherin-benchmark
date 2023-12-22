// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

import { IRewarder } from "./IRewarder.sol";
import { ISurgeStaking } from "./ISurgeStaking.sol";

contract HLPStaking is ISurgeStaking, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  error HLPStaking_InsufficientTokenAmount();
  error HLPStaking_NotRewarder();
  error HLPStaking_NotCompounder();
  error HLPStaking_DuplicateRewarder();
  error HLPStaking_WithdrawalNotAllowedDuringSurgeEvent();
  error HLPStaking_SurgeRewarderNotSet();
  error HLPStaking_SurgeEventEndEarlierThanStart();
  error HLPStaking_SurgeEventUnlockEarlierThanEnd();
  error HLPStaking_SurgeEventAlreadyStarted();
  error HLPStaking_SurgeEventAllTiersFilled();
  error HLPStaking_SurgeEventEnded();

  mapping(address => uint256) public userTokenAmount; // Track the staked HLP amount of each user
  mapping(address => mapping(uint256 => uint256)) public userTokenAmountByTier; // Track the staked HLP amount which is eligible in Surge Event of each user and each tier
  mapping(address => uint256) public userSurgeAmount; // Track the staked HLP amount which is eligible in Surge Event of each user for all tiers of that users
  mapping(uint256 => uint256) public totalQuoataByTier; // Track the remaining quota for each tier. Withdrawal will not replenish quota.
  mapping(uint256 => uint256) public totalAmountByTier; // Track the actual total amount for each tier.
  mapping(address => bool) public isRewarder;
  address[] public rewarders;
  TierConfig[] public tierConfigs;
  address public stakingToken;
  uint256 public startSurgeEventDepositTimestamp;
  uint256 public endSurgeEventDepositTimestamp;
  uint256 public endSurgeEventLockTimestamp;

  address public compounder;

  address public surgeRewarder;

  /// Delegate owner to perform migration on behalf of a user
  mapping(address user => bool isAllowed) public delegatedOf;

  event LogDelegate(address indexed user, address indexed delegate, bool isAllowed);
  event LogDeposit(address indexed caller, address indexed user, uint256 amount);
  event LogDepositTier(
    uint256 indexed tier,
    address indexed caller,
    address indexed user,
    uint256 amount
  );
  event LogWithdraw(address indexed caller, uint256 amount);
  event LogWithdrawTier(uint256 indexed tier, address indexed caller, uint256 amount);
  event LogAddRewarder(address newRewarder);
  event LogSetCompounder(address oldCompounder, address newCompounder);
  event LogSetTierConfig(uint256 indexed tier, TierConfig configs);
  event LogRemoveRewarder(uint256 indexed rewarderIndex, address indexed rewarder);
  event LogSetSurgeRewarder(address oldRewarder, address newRewarder);

  function initialize(
    address _stakingToken,
    uint256 _startSurgeEventDepositTimestamp,
    uint256 _endSurgeEventDepositTimestamp,
    uint256 _endSurgeEventLockTimestamp
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();

    if (_endSurgeEventDepositTimestamp < _startSurgeEventDepositTimestamp)
      revert HLPStaking_SurgeEventEndEarlierThanStart();
    if (_endSurgeEventLockTimestamp < _endSurgeEventDepositTimestamp)
      revert HLPStaking_SurgeEventUnlockEarlierThanEnd();

    stakingToken = _stakingToken;
    startSurgeEventDepositTimestamp = _startSurgeEventDepositTimestamp;
    endSurgeEventDepositTimestamp = _endSurgeEventDepositTimestamp;
    endSurgeEventLockTimestamp = _endSurgeEventLockTimestamp;
  }

  function addRewarders(address[] memory newRewarders) external onlyOwner {
    for (uint256 i = 0; i < newRewarders.length; ) {
      address newRewarder = newRewarders[i];
      if (isRewarder[newRewarder]) revert HLPStaking_DuplicateRewarder();

      rewarders.push(newRewarder);
      isRewarder[newRewarder] = true;

      emit LogAddRewarder(newRewarder);

      unchecked {
        ++i;
      }
    }
  }

  function removeRewarder(uint256 rewarderIndex) external onlyOwner {
    address rewarderToRemove = rewarders[rewarderIndex];
    rewarders[rewarderIndex] = rewarders[rewarders.length - 1];
    rewarders[rewarders.length - 1] = rewarderToRemove;
    rewarders.pop();
    isRewarder[rewarderToRemove] = false;

    emit LogRemoveRewarder(rewarderIndex, rewarderToRemove);
  }

  function setCompounder(address compounder_) external onlyOwner {
    emit LogSetCompounder(compounder, compounder_);
    compounder = compounder_;
  }

  function setSurgeRewarder(address _surgeRewarder) external onlyOwner {
    emit LogSetSurgeRewarder(surgeRewarder, _surgeRewarder);
    surgeRewarder = _surgeRewarder;
  }

  function setSurgeEventTime(
    uint256 _startSurgeEventDepositTimestamp,
    uint256 _endSurgeEventDepositTimestamp,
    uint256 _endSurgeEventLockTimestamp
  ) external onlyOwner {
    if (block.timestamp > startSurgeEventDepositTimestamp)
      revert HLPStaking_SurgeEventAlreadyStarted();
    if (_endSurgeEventDepositTimestamp < _startSurgeEventDepositTimestamp)
      revert HLPStaking_SurgeEventEndEarlierThanStart();
    if (_endSurgeEventLockTimestamp < _endSurgeEventDepositTimestamp)
      revert HLPStaking_SurgeEventUnlockEarlierThanEnd();

    startSurgeEventDepositTimestamp = _startSurgeEventDepositTimestamp;
    endSurgeEventDepositTimestamp = _endSurgeEventDepositTimestamp;
    endSurgeEventLockTimestamp = _endSurgeEventLockTimestamp;
  }

  function setTierConfigs(TierConfig[] memory configs) external onlyOwner {
    for (uint256 i = 0; i < configs.length; ) {
      tierConfigs.push(configs[i]);

      emit LogSetTierConfig(i, configs[i]);

      unchecked {
        ++i;
      }
    }
  }

  function delegate(bool allow) external {
    delegatedOf[msg.sender] = allow;
    emit LogDelegate(msg.sender, owner(), allow);
  }

  /// @notice Move stake from one address to another (including SURGEd HLP)
  /// @dev This function is used to migrate stake from one address to another.
  /// @dev Only executable if `from` and `to` delegate to `owner`
  /// @param from The address to move stake `from`
  /// @param to The address to move stake `to`
  function moveStake(address from, address to) external onlyOwner {
    require(delegatedOf[from] && delegatedOf[to], "!delegated");
    /// Withdraw from `from`
    /// 1. Clear non SURGEd HLP.
    uint256 nonSurgedHlpAmount = userTokenAmount[from];
    uint256 iterator = 0;
    for (iterator = 0; iterator < rewarders.length; ) {
      address rewarder = rewarders[iterator];
      if (rewarder != surgeRewarder) {
        IRewarder(rewarder).onWithdraw(from, nonSurgedHlpAmount);
      } else {
        // Force update the accRewardPerShare only, becuase we do not know the share amount yet
        IRewarder(rewarder).onWithdraw(from, 0);
      }
      unchecked {
        ++iterator;
      }
    }
    userTokenAmount[from] = 0;
    /// 2. Clear SURGEd HLP.
    uint256[] memory prevUserTokenAmountByTier = new uint256[](tierConfigs.length);
    uint256 prevUserSurgeAmount = userSurgeAmount[from];
    uint256 prevUserSurgedShare = calculateShareFromSurgeEvent(surgeRewarder, from);
    if (userSurgeAmount[from] > 0) {
      /// Only execute if user has SURGEd HLP.
      for (iterator = 0; iterator < tierConfigs.length; ) {
        uint256 userTokenAmountOfThisTier = userTokenAmountByTier[from][iterator];
        if (userTokenAmountOfThisTier > 0) {
          /// If user has SURGEd HLP in this tier.
          /// Then, clear the SURGEd HLP in this tier.
          /// Update the prev value for the userTokenAmountByTier
          prevUserTokenAmountByTier[iterator] = userTokenAmountOfThisTier;
          /// Clear the userTokenAmountByTier
          userTokenAmountByTier[from][iterator] = 0;
        }
        unchecked {
          ++iterator;
        }
      }
      /// Clear userSurgeAmount
      userSurgeAmount[from] = 0;
      /// Clear the SURGEd HLP shares
      IRewarder(surgeRewarder).onWithdraw(from, prevUserSurgedShare);
    }

    /// Deposit to `to`
    /// 1. Add non SURGEd HLP back.
    for (iterator = 0; iterator < rewarders.length; ) {
      address rewarder = rewarders[iterator];
      if (rewarder != surgeRewarder) {
        IRewarder(rewarder).onDeposit(to, nonSurgedHlpAmount);
      } else {
        // Force update the accRewardPerShare only, because we do not know the share amount yet
        IRewarder(rewarder).onDeposit(to, 0);
      }
      unchecked {
        ++iterator;
      }
    }
    userTokenAmount[to] += nonSurgedHlpAmount;
    /// 2. Add SURGEd HLP back.
    if (prevUserSurgeAmount > 0) {
      for (iterator = 0; iterator < prevUserTokenAmountByTier.length; ) {
        if (prevUserTokenAmountByTier[iterator] > 0) {
          /// Only execute if user has SURGEd HLP in this tier.
          userTokenAmountByTier[to][iterator] += prevUserTokenAmountByTier[iterator];
        }
        unchecked {
          ++iterator;
        }
      }
    }
    /// Add userSurgeAmount back
    userSurgeAmount[to] += prevUserSurgeAmount;
    /// Add the SURGEd HLP shares back
    IRewarder(surgeRewarder).onDeposit(to, prevUserSurgedShare);
  }

  function deposit(address to, uint256 amount) external {
    _deposit(to, amount, false);
  }

  function depositSurge(address to, uint256 amount) external {
    _deposit(to, amount, true);
  }

  function _deposit(address to, uint256 amount, bool isSurge) internal {
    if (surgeRewarder == address(0)) revert HLPStaking_SurgeRewarderNotSet();

    for (uint256 i = 0; i < rewarders.length; ) {
      address rewarder = rewarders[i];

      if (rewarder != surgeRewarder) {
        IRewarder(rewarder).onDeposit(to, amount);
      } else {
        // Force update the accRewardPerShare only, because we do not know the share amount yet
        IRewarder(rewarder).onDeposit(to, 0);
      }

      unchecked {
        ++i;
      }
    }

    userTokenAmount[to] += amount;

    // Surge HLP
    if (isSurge) {
      if (!isSurgeEventDepositPeriod()) revert HLPStaking_SurgeEventEnded();
      if (totalQuoataByTier[tierConfigs.length - 1] == tierConfigs[tierConfigs.length - 1].maxCap)
        revert HLPStaking_SurgeEventAllTiersFilled();
      uint256 userShareBefore = calculateShareFromSurgeEvent(surgeRewarder, to);
      uint256 remainingAmount = amount;
      for (uint256 tier = 0; tier < tierConfigs.length; ) {
        if (totalQuoataByTier[tier] < tierConfigs[tier].maxCap) {
          uint256 remainingQuotaForThisTier = tierConfigs[tier].maxCap - totalQuoataByTier[tier];
          if (remainingQuotaForThisTier > remainingAmount) {
            emit LogDepositTier(tier, msg.sender, to, remainingAmount);
            userTokenAmountByTier[to][tier] += remainingAmount;
            userSurgeAmount[to] += remainingAmount;
            totalAmountByTier[tier] += remainingAmount;
            totalQuoataByTier[tier] += remainingAmount;
            remainingAmount = 0;
          } else {
            emit LogDepositTier(tier, msg.sender, to, remainingQuotaForThisTier);
            userTokenAmountByTier[to][tier] += remainingQuotaForThisTier;
            userSurgeAmount[to] += remainingQuotaForThisTier;
            totalAmountByTier[tier] += remainingQuotaForThisTier;
            totalQuoataByTier[tier] += remainingQuotaForThisTier;
            remainingAmount -= remainingQuotaForThisTier;
          }
        }

        if (remainingAmount == 0) break;

        unchecked {
          ++tier;
        }
      }

      // Update the userRewardDebts with the newly added share
      uint256 diffUserShare = calculateShareFromSurgeEvent(surgeRewarder, to) - userShareBefore;
      IRewarder(surgeRewarder).onDeposit(to, diffUserShare);
    }

    IERC20Upgradeable(stakingToken).safeTransferFrom(msg.sender, address(this), amount);

    emit LogDeposit(msg.sender, to, amount);
  }

  function withdraw(uint256 amount) external {
    _withdraw(amount);
    emit LogWithdraw(msg.sender, amount);
  }

  function _withdraw(uint256 amount) internal {
    if (surgeRewarder == address(0)) revert HLPStaking_SurgeRewarderNotSet();
    if (userTokenAmount[msg.sender] < amount) revert HLPStaking_InsufficientTokenAmount();

    if (
      userSurgeAmount[msg.sender] > 0 &&
      amount > (userTokenAmount[msg.sender] - userSurgeAmount[msg.sender]) &&
      isSurgeEventLockPeriod()
    ) revert HLPStaking_WithdrawalNotAllowedDuringSurgeEvent();

    for (uint256 i = 0; i < rewarders.length; ) {
      address rewarder = rewarders[i];

      if (rewarder != surgeRewarder) {
        IRewarder(rewarder).onWithdraw(msg.sender, amount);
      } else {
        // Force update the accRewardPerShare only, becuase we do not know the share amount yet
        IRewarder(rewarder).onWithdraw(msg.sender, 0);
      }

      unchecked {
        ++i;
      }
    }
    userTokenAmount[msg.sender] -= amount;

    // If user still has balance in Surge Event and the withdawal would reach the Surge balance,
    // update the Surge state
    if (userTokenAmount[msg.sender] < userSurgeAmount[msg.sender]) {
      uint256 remainingAmount = userSurgeAmount[msg.sender] - userTokenAmount[msg.sender];
      if (!isSurgeEventLockPeriod() && userSurgeAmount[msg.sender] > 0) {
        uint256 userShareBefore = calculateShareFromSurgeEvent(surgeRewarder, msg.sender);

        for (uint256 tier = tierConfigs.length - 1; tier >= 0; ) {
          uint256 userTokenAmountOfThisTier = userTokenAmountByTier[msg.sender][tier];
          if (userTokenAmountOfThisTier > 0) {
            if (userTokenAmountOfThisTier > remainingAmount) {
              emit LogWithdrawTier(tier, msg.sender, remainingAmount);
              userTokenAmountByTier[msg.sender][tier] -= remainingAmount;
              userSurgeAmount[msg.sender] -= remainingAmount;
              totalAmountByTier[tier] -= remainingAmount;
              remainingAmount = 0;
            } else {
              emit LogWithdrawTier(tier, msg.sender, userTokenAmountOfThisTier);
              userTokenAmountByTier[msg.sender][tier] = 0;
              userSurgeAmount[msg.sender] -= userTokenAmountOfThisTier;
              totalAmountByTier[tier] -= userTokenAmountOfThisTier;
              remainingAmount -= userTokenAmountOfThisTier;
            }
          }

          if (remainingAmount == 0) break;

          unchecked {
            --tier;
          }
        }
        // Update the userRewardDebts with the newly added share
        uint256 diffUserShare = userShareBefore -
          calculateShareFromSurgeEvent(surgeRewarder, msg.sender);
        IRewarder(surgeRewarder).onWithdraw(msg.sender, diffUserShare);
      }
    }

    IERC20Upgradeable(stakingToken).safeTransfer(msg.sender, amount);

    emit LogWithdraw(msg.sender, amount);
  }

  function harvest(address[] memory _rewarders) external {
    _harvestFor(msg.sender, msg.sender, _rewarders);
  }

  function harvestToCompounder(address user, address[] memory _rewarders) external {
    if (compounder != msg.sender) revert HLPStaking_NotCompounder();
    _harvestFor(user, compounder, _rewarders);
  }

  function _harvestFor(address user, address receiver, address[] memory _rewarders) internal {
    uint256 length = _rewarders.length;
    for (uint256 i = 0; i < length; ) {
      if (!isRewarder[_rewarders[i]]) {
        revert HLPStaking_NotRewarder();
      }

      IRewarder(_rewarders[i]).onHarvest(user, receiver);

      unchecked {
        ++i;
      }
    }
  }

  function calculateShare(address /*rewarder*/, address user) external view returns (uint256) {
    return userTokenAmount[user];
  }

  function calculateShareFromSurgeEvent(
    address /*rewarder*/,
    address user
  ) public view returns (uint256) {
    uint256 inflatedShare = 0;
    for (uint256 tier = 0; tier < tierConfigs.length; ) {
      inflatedShare += userTokenAmountByTier[user][tier] * tierConfigs[tier].multiplier;

      unchecked {
        ++tier;
      }
    }
    return inflatedShare;
  }

  function calculateTotalShare(address /*rewarder*/) external view returns (uint256) {
    return IERC20Upgradeable(stakingToken).balanceOf(address(this));
  }

  function calculateTotalShareFromSurgeEvent(
    address /*rewarder*/
  ) external view returns (uint256 totalShare) {
    for (uint256 tier = 0; tier < tierConfigs.length; ) {
      totalShare += totalAmountByTier[tier] * tierConfigs[tier].multiplier;

      unchecked {
        ++tier;
      }
    }
    return totalShare;
  }

  function isSurgeEventDepositPeriod() public view returns (bool isActive) {
    return (block.timestamp >= startSurgeEventDepositTimestamp &&
      block.timestamp <= endSurgeEventDepositTimestamp);
  }

  function isSurgeEventLockPeriod() public view returns (bool isActive) {
    return block.timestamp <= endSurgeEventLockTimestamp;
  }

  function getRewarders() external view returns (address[] memory) {
    return rewarders;
  }

  function getTierConfigs() external view returns (TierConfig[] memory) {
    return tierConfigs;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

