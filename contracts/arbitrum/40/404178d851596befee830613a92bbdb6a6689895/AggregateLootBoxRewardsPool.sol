// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC1155.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./IRarityItemMinter.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";

import "./IRewardsPool.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./ManagerModifier.sol";
import "./Random.sol";

contract AggregateLootBoxRewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Structs
  //=======================================
  struct AggregateRewardsDistribution {
    address[] contracts;
    uint64[] subPoolIds;
    uint256[] contractChances;
    uint256 totalChance;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint64 => mapping(uint256 => AggregateRewardsDistribution))
    public rewardDistributions;
  mapping(uint64 => uint256) public rewardDistributionCount;

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  // Dispenses rewards based on a random roll and the chances defined for each rarity.
  function dispenseRewards(
    uint64 _subPoolId,
    uint256 _randomBase,
    address receiver
  )
    external
    onlyManager
    whenNotPaused
    returns (DispensedRewards memory allRewards)
  {
    uint256 distributionCount = rewardDistributionCount[_subPoolId];

    require(distributionCount > 0, "Uninitialized rewards pool");
    // There can be multiple reward branches for multiple rewards, so we'll store the array from each result separately
    DispensedReward[][] memory rewards = new DispensedReward[][](
      distributionCount
    );
    allRewards.nextRandomBase = _randomBase;
    uint256 roll;
    for (uint256 i = 0; i < distributionCount; i++) {
      AggregateRewardsDistribution storage dist = rewardDistributions[
        _subPoolId
      ][i];
      (roll, allRewards.nextRandomBase) = Random.getNextRandom(
        allRewards.nextRandomBase,
        dist.totalChance
      );
      for (uint256 j = 0; j < dist.contractChances.length; j++) {
        if (roll < dist.contractChances[j]) {
          // Drop rewards if contract is 0 (noop rewards implementation equivalent)
          if (address(dist.contracts[j]) == address(0)) {
            rewards[i] = new DispensedReward[](0);
            break;
          }

          // Dispense rewards
          DispensedRewards memory currentRewards = IRewardsPool(
            dist.contracts[j]
          ).dispenseRewards(
              dist.subPoolIds[j],
              allRewards.nextRandomBase,
              receiver
            );
          rewards[i] = currentRewards.rewards;
          allRewards.nextRandomBase = currentRewards.nextRandomBase;
          break;
        }
        roll -= dist.contractChances[j];
      }
      // Combine rewards in a single array
      allRewards.rewards = _concatenateRewards(rewards);
    }
  }

  //=======================================
  // Admin
  //=======================================
  function configureSubPool(
    uint64 _subPoolId,
    address[][] calldata _contracts,
    uint64[][] calldata _subPoolIds,
    uint256[][] calldata _contractChances
  ) external onlyAdmin {
    uint256 totalDraws = _contracts.length;
    require(totalDraws == _subPoolIds.length, "Incorrect subpool id config");
    require(
      totalDraws == _contractChances.length,
      "Incorrect contract chances config"
    );

    rewardDistributionCount[_subPoolId] = totalDraws;
    for (uint256 i = 0; i < totalDraws; i++) {
      require(_contracts[i].length == _subPoolIds[i].length);
      require(_contracts[i].length == _contractChances[i].length);

      uint256 totalChance = 0;
      for (uint64 j = 0; j < _contracts[i].length; j++) {
        totalChance += _contractChances[i][j];
      }
      rewardDistributions[_subPoolId][i] = AggregateRewardsDistribution(
        _contracts[i],
        _subPoolIds[i],
        _contractChances[i],
        totalChance
      );
    }
  }

  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }

  //=======================================
  // Internal
  //=======================================
  function _concatenateRewards(
    DispensedReward[][] memory rewards
  ) internal pure returns (DispensedReward[] memory) {
    if (rewards.length == 1) {
      return rewards[0];
    }

    uint totalLength = 0;
    for (uint i = 0; i < rewards.length; i++) {
      totalLength += rewards[i].length;
    }
    DispensedReward[] memory merged = new DispensedReward[](totalLength);

    uint k = 0;
    for (uint i = 0; i < rewards.length; i++) {
      for (uint j = 0; j < rewards[i].length; j++) {
        merged[k++] = rewards[i][j];
      }
    }

    return merged;
  }
}

