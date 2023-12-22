// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import { IStaker, IRewardDistributor_v2, IFeeClaimer } from "./interfaces.sol";

interface IRewardsCalculator {
  struct RewardInfo {
    uint256 rewardAmountLessFee;
    uint256 feeAmount;
    uint256 spaPerSecond;
    uint32 rewardsTill;
    bool isCheckpointed;
  }

  function checkpoints(uint256 _index)
    external
    view
    returns (
      uint256 rewardAmountLessFee,
      uint256 feeAmount,
      uint256 spaPerSecond,
      uint32 rewardsTill,
      bool isCheckpointed
    );

  function checkpointSpaRewards(
    uint256 index,
    uint256 weeklyRewardsLessFee,
    uint256 protocolFee,
    uint32 rewardsTill
  ) external;

  function calculateSpaRewards(uint256 lastRewardSecond, uint256 shares) external view returns (uint256 spaPerShare);

  error UNAUTHORIZED();
}

contract RewardsCalculator is IRewardsCalculator {
  uint256 private constant MUL_CONSTANT = 1e14;
  IRewardDistributor_v2 public constant UNDERLYING_FARM = IRewardDistributor_v2(address(0));
  address public constant STAKER = address(0);
  address public FEE_CLAIMER = address(0);

  mapping(uint256 => RewardInfo) public checkpoints;

  /**
   * Account for reward allocation across weeks
   */
  function calculateSpaRewards(uint256 lastRewardSecond, uint256 shares) external view returns (uint256 spaPerShare) {
    uint256 lastClaimedIndex = lastRewardSecond / 1 weeks;
    uint256 currentIndex = block.timestamp / 1 days;

    for (uint256 i = lastClaimedIndex; i < currentIndex; i++) {
      RewardInfo memory info = checkpoints[i];

      uint256 claimableSeconds = i == currentIndex ? info.rewardsTill - lastRewardSecond : 1 weeks;

      spaPerShare += (claimableSeconds * info.spaPerSecond * MUL_CONSTANT) / shares;
    }
  }

  /**
   * Checkpoint reward allocation
   */
  function checkpointSpaRewards(
    uint256 index,
    uint256 weeklyRewardsLessFee,
    uint256 protocolFee,
    uint32 rewardsTill
  ) external {
    if (msg.sender != FEE_CLAIMER) revert UNAUTHORIZED();

    uint256 spaPerSecond = weeklyRewardsLessFee / 7 days;

    checkpoints[index] = RewardInfo({
      rewardAmountLessFee: weeklyRewardsLessFee,
      feeAmount: protocolFee,
      spaPerSecond: spaPerSecond,
      rewardsTill: rewardsTill,
      isCheckpointed: true
    });
  }
}

