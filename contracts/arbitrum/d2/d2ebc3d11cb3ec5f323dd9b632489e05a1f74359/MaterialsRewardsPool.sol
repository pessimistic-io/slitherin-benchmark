// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Material.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";

contract MaterialsRewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Interfaces
  //=======================================
  Material public materialContract;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint64 => FragmentRewardsDistribution) public rewardDistributions;

  struct FragmentRewardsDistribution {
    uint256[] itemIds;
    uint256[] itemAmounts;
    uint256[] itemChances;
    uint256 totalChance;
  }

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, address _fragments) ManagerModifier(_manager) {
    materialContract = Material(_fragments);
  }

  //=======================================
  // External
  //=======================================
  function dispenseRewards(
    uint64 _subPoolId,
    uint256 _randomBase,
    address _receiver
  ) external onlyManager whenNotPaused returns (DispensedRewards memory) {
    FragmentRewardsDistribution storage dist = rewardDistributions[_subPoolId];

    DispensedReward[] memory rewards = new DispensedReward[](1);
    uint256 roll;
    (roll, _randomBase) = Random.getNextRandom(_randomBase, dist.totalChance);

    for (uint256 i = 0; i < dist.itemIds.length * 2; i++) {
      uint256 tokenIndex = i % dist.itemIds.length;
      if (roll < dist.itemChances[tokenIndex]) {
        // If there is enough balance in the bank, transfer the reward to the receiver
        materialContract.mintFor(
          _receiver,
          dist.itemIds[tokenIndex],
          dist.itemAmounts[tokenIndex]
        );

        rewards[0] = DispensedReward(
          RewardTokenType.ERC1155,
          address(materialContract),
          dist.itemIds[tokenIndex],
          dist.itemAmounts[tokenIndex]
        );
        return DispensedRewards(_randomBase, rewards);
      }
      roll -= dist.itemChances[tokenIndex];
    }

    // If the rewards pool is empty, and there is no backup pool we return 0 rewards
    return DispensedRewards(_randomBase, new DispensedReward[](0));
  }

  //=======================================
  // Admin
  //=======================================
  function configureSubPool(
    uint64 _subPoolId,
    uint256[] calldata _itemAmounts,
    uint256[] calldata _itemIds,
    uint256[] calldata _itemChances
  ) external onlyAdmin {
    require(_itemAmounts.length == _itemIds.length);
    require(_itemAmounts.length == _itemChances.length);

    uint256 totalChance = 0;
    for (uint256 i = 0; i < _itemIds.length; i++) {
      totalChance += _itemChances[i];
    }

    FragmentRewardsDistribution memory dist = FragmentRewardsDistribution(
      _itemIds,
      _itemAmounts,
      _itemChances,
      totalChance
    );
    rewardDistributions[_subPoolId] = dist;
  }

  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

