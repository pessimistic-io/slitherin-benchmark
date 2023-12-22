// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./Ownable2Step.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import { IRewardDistributor, IRewardTracker } from "./Interfaces.sol";

contract RewardDistributor is IRewardDistributor, Ownable2Step {
  using SafeERC20 for IERC20;
  uint private constant BASIS_POINTS_DIVISOR = 1e4;

  address public immutable rewardToken;
  address public immutable rewardTracker;

  uint128 public tokensPerSecond;
  uint128 public lastDistributionTime;
  bool public isInitialized;

  constructor(address _rewardToken, address _rewardTracker) {
    rewardToken = _rewardToken;
    rewardTracker = _rewardTracker;
  }

  function pendingRewards() public view override returns (uint) {
    if (block.timestamp == lastDistributionTime) {
      return 0;
    }

    unchecked {
      return (block.timestamp - lastDistributionTime) * tokensPerSecond;
    }
  }

  function getRate() public pure returns (uint256) {
    return BASIS_POINTS_DIVISOR;
  }

  function distribute() external override returns (uint) {
    if (msg.sender != rewardTracker) revert UNAUTHORIZED('RewardDistributor: !rewardTracker');

    uint amount = pendingRewards();
    if (amount == 0) {
      lastDistributionTime = uint128(block.timestamp);
      return 0;
    }

    lastDistributionTime = uint128(block.timestamp);
    uint balance = IERC20(rewardToken).balanceOf(address(this));

    if (amount > balance) {
      amount = balance;
    }

    IERC20(rewardToken).safeTransfer(rewardTracker, amount);

    emit Distribute(amount);
    return amount;
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function updateLastDistributionTime() external onlyOwner {
    if (isInitialized) revert FAILED('RewardDistributor: already initialized');
    isInitialized = true;
    lastDistributionTime = uint128(block.timestamp);
  }

  function setTokensPerSecond(uint128 _amount) external onlyOwner {
    if (lastDistributionTime == 0) revert FAILED('RewardDistributor: invalid lastDistributionTime');
    IRewardTracker(rewardTracker).updateRewards();
    tokensPerSecond = _amount;

    emit TokensPerSecondChange(_amount);
  }
}

