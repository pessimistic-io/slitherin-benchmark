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
import { SafeCastUpgradeable } from "./SafeCastUpgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";

import { IRewarder } from "./IRewarder.sol";
import { IStaking } from "./IStaking.sol";
import { MintableTokenInterface } from "./MintableTokenInterface.sol";

contract AdHocMintRewarder is OwnableUpgradeable {
  using SafeCastUpgradeable for uint256;
  using SafeCastUpgradeable for uint128;
  using SafeCastUpgradeable for int256;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  string public name;
  address public rewardToken;
  address public staking;

  // Reward calculation parameters
  uint64 constant YEAR = 365 days;
  mapping(address => uint64) public userLastRewards;
  mapping(address => uint256) public userAccRewards;

  uint256 public rewardRate;

  // Events
  event LogOnDeposit(address indexed user, uint256 shareAmount);
  event LogOnWithdraw(address indexed user, uint256 shareAmount);
  event LogHarvest(address indexed user, uint256 pendingRewardAmount);

  // Error
  error AdHocMintRewarderError_NotStakingContract();

  modifier onlyStakingContract() {
    if (msg.sender != staking) revert AdHocMintRewarderError_NotStakingContract();
    _;
  }

  function initialize(
    string memory name_,
    address rewardToken_,
    address staking_
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();

    // Sanity check
    IERC20Upgradeable(rewardToken_).totalSupply();
    IStaking(staking_).isRewarder(address(this));
    name = name_;
    rewardToken = rewardToken_;
    staking = staking_;

    // For compatability only, no calculation usage on chain
    rewardRate = 31709791983 wei; // = 1 ether / 365 day
  }

  function onDeposit(address user, uint256 shareAmount) external onlyStakingContract {
    // Accumulate user reward
    userAccRewards[user] += _calculateUserAccReward(user);
    userLastRewards[user] = block.timestamp.toUint64();
    emit LogOnDeposit(user, shareAmount);
  }

  function onWithdraw(address user, uint256 shareAmount) external onlyStakingContract {
    // Reset user reward
    // The rule is whenever withdraw occurs, no matter the size, reward calculation should restart.
    userAccRewards[user] = 0;
    userLastRewards[user] = block.timestamp.toUint64();
    emit LogOnWithdraw(user, shareAmount);
  }

  function onHarvest(address user, address receiver) external onlyStakingContract {
    uint256 pendingRewardAmount = _pendingReward(user);

    // Reset user reward accumulation.
    // The next action will start accum reward from zero again.
    userAccRewards[user] = 0;
    userLastRewards[user] = block.timestamp.toUint64();

    if (pendingRewardAmount != 0) {
      _harvestToken(receiver, pendingRewardAmount);
    }

    emit LogHarvest(user, pendingRewardAmount);
  }

  function pendingReward(address user) external view returns (uint256) {
    return _pendingReward(user);
  }

  function _pendingReward(address user) internal view returns (uint256) {
    // (accumulated reward since the last action) + (jotted reward from the past)
    return _calculateUserAccReward(user) + userAccRewards[user];
  }

  function _calculateUserAccReward(address user) internal view returns (uint256) {
    // [100% APR] If a user stake N shares for a year, he will be rewarded with N tokens.
    if (userLastRewards[user] > 0) {
      return ((block.timestamp - userLastRewards[user]) * _userShare(user)) / YEAR;
    } else {
      return 0;
    }
  }

  function _userShare(address user) private view returns (uint256) {
    return IStaking(staking).calculateShare(address(this), user);
  }

  function _harvestToken(address receiver, uint256 pendingRewardAmount) internal virtual {
    MintableTokenInterface(rewardToken).mint(receiver, pendingRewardAmount);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }
}

