// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./Ownable2Step.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import { IBonusDistributor, IRewardTracker } from "./Interfaces.sol";
import { IRateProvider } from "./RateProvider.sol";

contract BonusDistributor is IBonusDistributor, Ownable2Step {
  using SafeERC20 for IERC20;
  uint private constant BASIS_POINTS_DIVISOR = 1e4;
  uint private constant BONUS_DURATION = 365 days;

  address public immutable rewardToken;
  address public immutable rewardTracker;
  address public rateProvider;

  uint128 public bonusMultiplierBasisPoints;
  uint128 public lastDistributionTime;
  bool public isInitialized;

  constructor(address _rewardToken, address _rewardTracker) {
    rewardToken = _rewardToken;
    rewardTracker = _rewardTracker;
  }

  function tokensPerSecond() external view override returns (uint128) {
    uint supply = IERC20(rewardTracker).totalSupply();

    unchecked {
      return
        uint128(
          (supply * getRate() * bonusMultiplierBasisPoints) /
            BASIS_POINTS_DIVISOR /
            BASIS_POINTS_DIVISOR /
            BONUS_DURATION
        );
    }
  }

  function pendingRewards() public view override returns (uint) {
    if (block.timestamp == lastDistributionTime) {
      return 0;
    }

    uint supply = IERC20(rewardTracker).totalSupply();

    unchecked {
      return
        ((block.timestamp - lastDistributionTime) * supply * getRate() * bonusMultiplierBasisPoints) /
        BASIS_POINTS_DIVISOR /
        BASIS_POINTS_DIVISOR /
        BONUS_DURATION;
    }
  }

  function distribute() external override returns (uint) {
    if (msg.sender != rewardTracker) revert UNAUTHORIZED('BonusDistributor: !rewardTracker');

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

  function getRate() public view returns (uint256) {
    if (rateProvider == address(0)) return BASIS_POINTS_DIVISOR;

    return IRateProvider(rateProvider).getRate();
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function setRateProvider(address _rateProvider) external onlyOwner {
    rateProvider = _rateProvider;
  }

  function updateLastDistributionTime() external onlyOwner {
    if (isInitialized) revert FAILED('BonusDistributor: already initialized');
    isInitialized = true;
    lastDistributionTime = uint128(block.timestamp);
  }

  function setBonusMultiplier(uint128 _bonusMultiplierBasisPoints) external onlyOwner {
    if (lastDistributionTime == 0) revert FAILED('BonusDistributor: invalid lastDistributionTime');
    IRewardTracker(rewardTracker).updateRewards();

    bonusMultiplierBasisPoints = _bonusMultiplierBasisPoints;

    emit BonusMultiplierChange(_bonusMultiplierBasisPoints);
  }
}

