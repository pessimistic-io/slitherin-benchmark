// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8;

import "./IRewardDistributor.sol";
import "./IRewardTracker.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";

contract RewardDistributor is IRewardDistributor, OwnableUpgradeable, AccessControlUpgradeable {
  using SafeERC20 for IERC20;

  bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');

  address public override rewardToken;
  uint256 public override tokensPerInterval;
  uint256 public lastDistributionTime;
  IRewardTracker public rewardTracker;

  function initialize(
    address _owner,
    address _rewardToken,
    uint256 _tokensPerInterval
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    AccessControlUpgradeable.__AccessControl_init();

    _transferOwnership(_owner);
    _setupRole(DEFAULT_ADMIN_ROLE, _owner);

    rewardToken = _rewardToken;
    tokensPerInterval = _tokensPerInterval;

    _updateLastDistributionTime();
  }

  function updateLastDistributionTime() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateLastDistributionTime();
  }

  function setTokensPerInterval(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(lastDistributionTime != 0, 'RewardDistributor: invalid lastDistributionTime');
    rewardTracker.updateRewards();
    tokensPerInterval = _amount;

    emit TokensPerIntervalChange(_amount);
  }

  function setRewardTracker(IRewardTracker _rewardTracker) external onlyRole(DEFAULT_ADMIN_ROLE) {
    rewardTracker = _rewardTracker;
  }

  function pendingRewards() public view override returns (uint256) {
    if (block.timestamp == lastDistributionTime) {
      return 0;
    }

    uint256 timeDiff = block.timestamp - lastDistributionTime;

    return tokensPerInterval * timeDiff;
  }

  function withdrawToken(
        address _token,
        address _account,
        uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    IERC20(_token).safeTransfer(_account, _amount);
  }

  function distribute() external override onlyRole(OPERATOR_ROLE) returns (uint256) {
    uint256 amount = pendingRewards();
    if (amount == 0) {
      return 0;
    }

    lastDistributionTime = block.timestamp;

    uint256 balance = IERC20(rewardToken).balanceOf(address(this));
    if (amount > balance) {
      amount = balance;
    }

    IERC20(rewardToken).safeTransfer(msg.sender, amount);

    emit Distribute(amount);

    return amount;
  }

  function _updateLastDistributionTime() private {
    lastDistributionTime = block.timestamp;
  }
}

