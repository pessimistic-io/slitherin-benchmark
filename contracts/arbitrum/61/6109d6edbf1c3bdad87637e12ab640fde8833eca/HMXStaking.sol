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
import { IHMXStaking } from "./IHMXStaking.sol";
import { DragonPoint } from "./DragonPoint.sol";
import { IVester } from "./IVester.sol";

contract HMXStaking is OwnableUpgradeable, IHMXStaking {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  uint256 private constant SIX_MONTHS = 180 days;

  // Events
  event LogAddStakingToken(address newToken, address[] newRewarders);
  event LogAddRewarder(address newRewarder, address[] newTokens);
  event LogSetCompounder(address oldCompounder, address newCompounder);
  event LogDeposit(address indexed caller, address indexed user, address token, uint256 amount);
  event LogWithdraw(address indexed caller, address token, uint256 amount);
  event LogSetAllRewarders(address[] oldRewarders, address[] newRewarders);
  event LogSetAllStakingTokens(address[] oldStakingTokens, address[] newStakingTokens);
  event LogAddLockedReward(
    address indexed account,
    address reward,
    uint256 amount,
    uint256 endRewardLockTimestamp
  );

  // Errors
  error HMXStaking_BadDecimals();
  error HMXStaking_InvalidTokenAmount();
  error HMXStaking_UnknownStakingToken();
  error HMXStaking_InsufficientTokenAmount();
  error HMXStaking_NotRewarder();
  error HMXStaking_NotCompounder();
  error HMXStaking_OnlyLHMXStakingTokenAllowed();
  error HMXStaking_RemainUnclaimReward();
  error HMXStaking_DragonPointWithdrawForbid();

  /**
   * States
   */

  // stakingToken => amount
  mapping(address => mapping(address => uint256)) public userTokenAmount;
  mapping(address => bool) public isStakingLHMX;
  mapping(address => bool) public isRewarder;
  mapping(address => bool) public isStakingToken;
  mapping(address => address[]) public stakingTokenRewarders;
  mapping(address => address[]) public rewarderStakingTokens;
  mapping(address => LockedReward[]) public userLockedRewards;
  mapping(address => uint256) public userLockedRewardsStartIndex;

  address public lhmx;
  address public compounder;
  address[] public allRewarders; // keeping all existing rewarders
  address[] public allStakingTokens; // keeping all existing staking tokens

  DragonPoint public dp;
  IRewarder public dragonPointRewarder;
  address public esHmx;
  address public vester;

  function initialize(
    address lhmx_,
    address dp_,
    address esHmx_,
    address vester_
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    lhmx = lhmx_;
    dp = DragonPoint(dp_);
    esHmx = esHmx_;
    vester = vester_;

    // Sanity check
    ERC20Upgradeable(lhmx).decimals();
    dp.decimals();
    ERC20Upgradeable(esHmx).decimals();
    IVester(vester).itemLastIndex(address(this));

    // Unlimited approve vester
    IERC20Upgradeable(esHmx).approve(vester, type(uint256).max);
  }

  function addStakingToken(
    address newStakingToken,
    address[] memory newRewarders
  ) external onlyOwner {
    if (ERC20Upgradeable(newStakingToken).decimals() != 18) revert HMXStaking_BadDecimals();

    uint256 length = newRewarders.length;
    for (uint256 i = 0; i < length; ) {
      _updatePool(newStakingToken, newRewarders[i]);

      emit LogAddStakingToken(newStakingToken, newRewarders);
      unchecked {
        ++i;
      }
    }
  }

  function addRewarder(address newRewarder, address[] memory newStakingToken) external onlyOwner {
    uint256 length = newStakingToken.length;
    for (uint256 i = 0; i < length; ) {
      if (ERC20Upgradeable(newStakingToken[i]).decimals() != 18) revert HMXStaking_BadDecimals();
      _updatePool(newStakingToken[i], newRewarder);

      emit LogAddRewarder(newRewarder, newStakingToken);
      unchecked {
        ++i;
      }
    }
  }

  /// @dev Removes a rewarder from an array of rewarders for a given staking token, as well as removing the staking token from the rewarder's array of staking tokens.
  /// @param removeRewarderIndex The index of the rewarder to remove from the array of rewarders for the staking token.
  /// @param stakingToken The address of the staking token associated with the rewarder.
  function removeRewarderFoStakingTokenByIndex(
    uint256 removeRewarderIndex,
    address stakingToken
  ) external onlyOwner {
    address removedRewarder = stakingTokenRewarders[stakingToken][removeRewarderIndex];
    {
      // Replace the rewarder to be removed with the last rewarder in the array and then remove it from the array.
      uint256 tokenLength = stakingTokenRewarders[stakingToken].length;
      stakingTokenRewarders[stakingToken][removeRewarderIndex] = stakingTokenRewarders[
        stakingToken
      ][tokenLength - 1];
      stakingTokenRewarders[stakingToken].pop();
    }

    {
      // Find the index of the staking token in the rewarder's array of staking tokens and remove it.
      uint256 rewarderLength = rewarderStakingTokens[removedRewarder].length;
      for (uint256 i = 0; i < rewarderLength; ) {
        if (rewarderStakingTokens[removedRewarder][i] == stakingToken) {
          rewarderStakingTokens[removedRewarder][i] = rewarderStakingTokens[removedRewarder][
            rewarderLength - 1
          ];
          rewarderStakingTokens[removedRewarder].pop();
          // If this is the only staking token associated with the rewarder, remove the rewarder.
          if (rewarderLength == 1) isRewarder[removedRewarder] = false;
          break;
        }
        unchecked {
          ++i;
        }
      }
    }
  }

  /// @dev Deposits an amount of a given staking token for a specified user, calling each associated rewarder's `onDeposit` function.
  /// @param account The address of the user depositing the staking token.
  /// @param token The address of the staking token being deposited.
  /// @param amount The amount of the staking token being deposited.
  function deposit(address account, address token, uint256 amount) external {
    _deposit(account, token, amount);
  }

  /// @dev Helper function that performs the deposit logic for the deposit() function.
  /// @param account The address of the user depositing the staking token.
  /// @param stakingToken The address of the staking token being deposited.
  /// @param amount The amount of the staking token being deposited.
  function _deposit(address account, address stakingToken, uint256 amount) internal {
    // Verify that the staking token is a known staking token in the contract.
    if (!isStakingToken[stakingToken]) revert HMXStaking_UnknownStakingToken();

    // Verify that only lhmx allowed for staking at the same time.
    {
      if (stakingToken != lhmx && userTokenAmount[lhmx][account] > 0)
        revert HMXStaking_OnlyLHMXStakingTokenAllowed();
      if (stakingToken == lhmx) {
        for (uint256 i = 0; i < allStakingTokens.length; ) {
          if (allStakingTokens[i] != lhmx && userTokenAmount[allStakingTokens[i]][account] > 0)
            revert HMXStaking_OnlyLHMXStakingTokenAllowed();
          unchecked {
            ++i;
          }
        }
      }
    }

    // If used to stake LHMX and switch to other tokens, or used to stake other tokens and switch to LHMX
    bool isSwitchStakingType = (isStakingLHMX[account] && stakingToken != lhmx) ||
      (!isStakingLHMX[account] && stakingToken == lhmx);

    if (isSwitchStakingType) {
      // Verify if there are remaining unclaimed rewards from LHMX staking or other tokens staking
      address[] memory _rewarders = isStakingLHMX[account]
        ? stakingTokenRewarders[lhmx]
        : allRewarders;
      for (uint256 i = 0; i < _rewarders.length; ) {
        if (isRewarder[_rewarders[i]] && IRewarder(_rewarders[i]).pendingReward(account) > 0) {
          revert HMXStaking_RemainUnclaimReward();
        }
        unchecked {
          ++i;
        }
      }

      // Toggle the staking type flag
      isStakingLHMX[account] = !isStakingLHMX[account];
    }

    // Call each associated rewarder's `onDeposit` function.
    address[] storage rewarders = stakingTokenRewarders[stakingToken];
    for (uint256 i = 0; i < rewarders.length; ) {
      IRewarder(rewarders[i]).onDeposit(account, amount);
      unchecked {
        ++i;
      }
    }

    // Add the deposited amount to the user's token balance and transfer the staking token to the contract.
    userTokenAmount[stakingToken][account] += amount;
    IERC20Upgradeable(stakingToken).safeTransferFrom(msg.sender, address(this), amount);

    // Emit a LogDeposit event.
    emit LogDeposit(msg.sender, account, stakingToken, amount);
  }

  /// @dev Withdraws an amount of a given staking token for the calling user, burning Dragon Points and depositing the remaining balance.
  /// @param stakingToken The address of the staking token being withdrawn.
  /// @param amount The amount of the staking token being withdrawn.
  function withdraw(address stakingToken, uint256 amount) public {
    if (amount == 0) revert HMXStaking_InvalidTokenAmount();
    if (stakingToken == address(dp)) revert HMXStaking_DragonPointWithdrawForbid();

    // Clear all of user dragon point
    dragonPointRewarder.onHarvest(msg.sender, msg.sender);
    _withdraw(address(dp), userTokenAmount[address(dp)][msg.sender]);

    // Withdraw the actual token, while we note down the share before/after (which already exclude Dragon Point)
    uint256 shareBefore = _calculateShare(address(dragonPointRewarder), msg.sender);
    _withdraw(stakingToken, amount);
    uint256 shareAfter = _calculateShare(address(dragonPointRewarder), msg.sender);

    // Find the burn amount
    uint256 dpBalance = dp.balanceOf(msg.sender);
    uint256 targetDpBalance = shareBefore > 0 ? (dpBalance * shareAfter) / shareBefore : 0;
    uint256 amountToBurn = dpBalance - targetDpBalance;

    // Burn from user, transfer the rest to here, and got depositted
    if (amountToBurn > 0) dp.burn(msg.sender, dpBalance - targetDpBalance);
    if (dp.balanceOf(msg.sender) > 0) _deposit(msg.sender, address(dp), dp.balanceOf(msg.sender));
  }

  /**
   * @dev Helper function that withdraws an amount of a given staking token for the calling user.
   * @param stakingToken The address of the staking token being withdrawn.
   * @param amount The amount of the staking token being withdrawn.
   */
  function _withdraw(address stakingToken, uint256 amount) internal {
    // Verify that the staking token is a known staking token in the contract.
    if (!isStakingToken[stakingToken]) revert HMXStaking_UnknownStakingToken();

    // Verify that the user has enough tokens to withdraw.
    if (userTokenAmount[stakingToken][msg.sender] < amount)
      revert HMXStaking_InsufficientTokenAmount();

    // Call each associated rewarder's `onWithdraw` function.
    uint256 length = stakingTokenRewarders[stakingToken].length;
    for (uint256 i = 0; i < length; ) {
      address rewarder = stakingTokenRewarders[stakingToken][i];
      IRewarder(rewarder).onWithdraw(msg.sender, amount);
      unchecked {
        ++i;
      }
    }

    // Subtract the withdrawn amount from the user's token balance and transfer the staking token to the user.
    userTokenAmount[stakingToken][msg.sender] -= amount;
    IERC20Upgradeable(stakingToken).safeTransfer(msg.sender, amount);

    // Emit a LogWithdraw event.
    emit LogWithdraw(msg.sender, stakingToken, amount);
  }

  function vestEsHmx(uint256 amount, uint256 duration) external {
    if (amount > userTokenAmount[esHmx][msg.sender] || amount == 0)
      revert HMXStaking_InvalidTokenAmount();
    withdraw(esHmx, amount);
    IERC20Upgradeable(esHmx).safeTransferFrom(msg.sender, address(this), amount);
    IVester(vester).vestFor(msg.sender, amount, duration);
  }

  /// @dev Harvests rewards for the calling user and transfers them to the same user.
  /// @param rewarders An array of rewarder addresses whose rewards are being harvested.
  function harvest(address[] memory rewarders) external {
    // Call the internal _harvestFor function with the same user as the receiver.
    _harvestFor(msg.sender, msg.sender, rewarders);
  }

  function harvestToCompounder(address user, address[] memory _rewarders) external {
    if (compounder != msg.sender) revert HMXStaking_NotCompounder();
    _harvestFor(user, compounder, _rewarders);
  }

  /// @dev Helper function that harvests rewards for a given user and transfers them to a given receiver.
  /// @param user The address of the user whose rewards are being harvested.
  /// @param receiver The address of the receiver for the harvested rewards.
  /// @param rewarders An array of rewarder addresses whose rewards are being harvested.
  function _harvestFor(address user, address receiver, address[] memory rewarders) internal {
    // Loop over each rewarder address and call its `onHarvest` function if it is a registered rewarder.
    uint256 length = rewarders.length;
    for (uint256 i = 0; i < length; ) {
      // Check if the current rewarder is registered, otherwise revert the transaction.
      if (!isRewarder[rewarders[i]]) revert HMXStaking_NotRewarder();

      // If the user's current staking token is not LHMX, all rewards can be claimed immediately.
      if (!isStakingLHMX[user]) {
        IRewarder(rewarders[i]).onHarvest(user, receiver);
      }
      // If the user's current staking token is LHMX, 50% of rewards can be claimed immediately, while the rest will be locked for 6 months.
      else {
        // Get the reward token associated with the current rewarder.
        address rewardToken = IRewarder(rewarders[i]).rewardToken();
        uint256 rewardAmountBefore = ERC20Upgradeable(rewardToken).balanceOf(address(this));

        IRewarder(rewarders[i]).onHarvest(user, address(this));

        // Calculate the amount of rewards received by subtracting the previous balance from the current balance.
        uint256 rewardRecieved = ERC20Upgradeable(rewardToken).balanceOf(address(this)) -
          rewardAmountBefore;

        if (rewardRecieved > 0) {
          // Calculate the claimable amount, which is half of the received rewards.
          uint256 claimAbleAmount = rewardRecieved / 2;

          // Store the locked rewards for the user, including the remaining amount and the lock period.
          userLockedRewards[user].push(
            LockedReward({
              account: user,
              reward: rewardToken,
              amount: rewardRecieved - claimAbleAmount,
              endRewardLockTimestamp: block.timestamp + SIX_MONTHS
            })
          );

          emit LogAddLockedReward(
            user,
            rewardToken,
            rewardRecieved - claimAbleAmount,
            block.timestamp + SIX_MONTHS
          );

          // Transfer claimable token to receiver
          IERC20Upgradeable(rewardToken).safeTransfer(receiver, claimAbleAmount);
        }
      }

      unchecked {
        ++i;
      }
    }
  }

  /// @dev Claims locked rewards for a given user.
  /// @param user The address of the user claiming the locked rewards.
  function claimLockedReward(address user) external {
    // Get the array of locked rewards for the user
    LockedReward[] storage lockedRewards = userLockedRewards[user];
    uint256 length = lockedRewards.length;

    for (uint256 i = userLockedRewardsStartIndex[user]; i < length; ) {
      // Check if the reward lock period has ended
      if (lockedRewards[i].endRewardLockTimestamp > block.timestamp) {
        // Update the start index for the user
        userLockedRewardsStartIndex[user] = i;
        break;
      }

      // Transfer the locked reward to the user's account
      IERC20Upgradeable(lockedRewards[i].reward).safeTransfer(
        lockedRewards[i].account,
        lockedRewards[i].amount
      );

      // Remove the claimed reward from the lockedRewards array
      delete lockedRewards[i];

      // Check if it was the last index
      if (i == length - 1) userLockedRewardsStartIndex[user] = length;

      unchecked {
        ++i;
      }
    }
  }

  /// @dev Calculates the share of a given user in a given rewarder.
  /// @param rewarder The address of the rewarder.
  /// @param user The address of the user.
  /// @return The share of the user in the rewarder.
  function calculateShare(address rewarder, address user) external view returns (uint256) {
    return _calculateShare(rewarder, user);
  }

  /// @dev Helper function that calculates the share of a given user in a given rewarder.
  /// @param rewarder The address of the rewarder.
  /// @param user The address of the user.
  /// @return The share of the user in the rewarder.
  function _calculateShare(address rewarder, address user) internal view returns (uint256) {
    // Get the staking tokens associated with the rewarder and calculate the user's share in each.
    address[] memory stakingTokens = rewarderStakingTokens[rewarder];
    uint256 share = 0;
    uint256 length = stakingTokens.length;

    for (uint256 i = 0; i < length; ) {
      share += userTokenAmount[stakingTokens[i]][user];
      unchecked {
        ++i;
      }
    }
    return share;
  }

  function calculateTotalShare(address rewarder) external view returns (uint256) {
    address[] memory stakingTokens = rewarderStakingTokens[rewarder];
    uint256 totalShare = 0;
    uint256 length = stakingTokens.length;
    for (uint256 i = 0; i < length; ) {
      totalShare += IERC20Upgradeable(stakingTokens[i]).balanceOf(address(this));
      unchecked {
        ++i;
      }
    }
    return totalShare;
  }

  /**
   * Setter
   */

  function setCompounder(address _compounder) external onlyOwner {
    emit LogSetCompounder(compounder, _compounder);
    compounder = _compounder;
  }

  function setAllRewarders(address[] memory _allRewarders) external onlyOwner {
    emit LogSetAllRewarders(allRewarders, _allRewarders);
    allRewarders = _allRewarders;
  }

  function setAllStakingTokens(address[] memory _allStakingTokens) external onlyOwner {
    emit LogSetAllStakingTokens(allStakingTokens, _allStakingTokens);
    allStakingTokens = _allStakingTokens;
  }

  function setDragonPointRewarder(address rewarder) external onlyOwner {
    dragonPointRewarder = IRewarder(rewarder);
  }

  function setDragonPoint(address _dp) external onlyOwner {
    dp = DragonPoint(_dp);
  }

  /**
   * Getters
   */
  function getUserTokenAmount(
    address stakingToken,
    address account
  ) external view returns (uint256) {
    return userTokenAmount[stakingToken][account];
  }

  function getUserLockedRewards(address account) external view returns (LockedReward[] memory) {
    return userLockedRewards[account];
  }

  function getStakingTokenRewarders(address stakingToken) external view returns (address[] memory) {
    return stakingTokenRewarders[stakingToken];
  }

  function getRewarderStakingTokens(address rewarder) external view returns (address[] memory) {
    return rewarderStakingTokens[rewarder];
  }

  function getAllRewarders() external view returns (address[] memory) {
    return allRewarders;
  }

  function getAllStakingTokens() external view returns (address[] memory) {
    return allStakingTokens;
  }

  function getAccumulatedLockedReward(
    address user,
    address[] memory rewards,
    bool isOnlyClaimAble
  ) external view returns (address[] memory, uint256[] memory) {
    LockedReward[] storage lockedRewards = userLockedRewards[user];
    uint256[] memory lockedAmounts = new uint256[](rewards.length);

    for (uint256 i = userLockedRewardsStartIndex[user]; i < lockedRewards.length; ) {
      if (isOnlyClaimAble && lockedRewards[i].endRewardLockTimestamp > block.timestamp) break;

      for (uint256 j = 0; i < rewards.length; ) {
        if (lockedRewards[i].reward == rewards[j]) {
          lockedAmounts[j] = lockedRewards[i].amount;
          break;
        }

        unchecked {
          ++j;
        }
      }

      unchecked {
        ++i;
      }
    }

    return (rewards, lockedAmounts);
  }

  /**
   * Private Functions
   */

  /// @notice
  function _updatePool(address newToken, address newRewarder) internal {
    if (!_isDuplicatedRewarder(newToken, newRewarder)) {
      stakingTokenRewarders[newToken].push(newRewarder);
    }
    if (!_isDuplicatedStakingToken(newToken, newRewarder)) {
      rewarderStakingTokens[newRewarder].push(newToken);
    }

    // update new staking token
    isStakingToken[newToken] = true;

    // update new rewarding token
    if (!isRewarder[newRewarder]) {
      isRewarder[newRewarder] = true;
    }
  }

  /// @notice check whether this staking token already contained new reward token
  function _isDuplicatedRewarder(
    address stakingToken,
    address rewarder
  ) internal view returns (bool) {
    uint256 length = stakingTokenRewarders[stakingToken].length;
    for (uint256 i = 0; i < length; ) {
      if (stakingTokenRewarders[stakingToken][i] == rewarder) return true;
      unchecked {
        ++i;
      }
    }
    return false;
  }

  /// @notice check whether this reward token already contained in satking token
  function _isDuplicatedStakingToken(
    address stakingToken,
    address rewarder
  ) internal view returns (bool) {
    uint256 length = rewarderStakingTokens[rewarder].length;
    for (uint256 i = 0; i < length; ) {
      if (rewarderStakingTokens[rewarder][i] == stakingToken) return true;
      unchecked {
        ++i;
      }
    }
    return false;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

