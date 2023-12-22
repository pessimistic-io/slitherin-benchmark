// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Strings.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./IRarityItemMinter.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";

contract RealmRarityItemLootBoxRewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Interfaces
  //=======================================
  IRarityItemMinter public rarityItemMinter;

  //=======================================
  // Structs
  //=======================================
  struct RarityItemRewardsDistribution {
    uint16[] itemRarities;
    uint256[] itemChances;
    uint256 totalChance;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint64 => RarityItemRewardsDistribution) public rewardDistributions;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _rarityItemMinter
  ) ManagerModifier(_manager) {
    rarityItemMinter = IRarityItemMinter(_rarityItemMinter);
  }

  //=======================================
  // External
  //=======================================
  function dispenseRewards(
    uint64 _subPoolId,
    uint256 _randomBase,
    address _receiver
  ) external onlyManager whenNotPaused returns (DispensedRewards memory) {
    RarityItemRewardsDistribution storage dist = rewardDistributions[
      _subPoolId
    ];
    require(dist.totalChance > 0, Strings.toString(_subPoolId));

    uint256 roll;
    uint256 mintedId;
    address mintedCollection;
    DispensedReward[] memory rewards = new DispensedReward[](1);
    (roll, _randomBase) = Random.getNextRandom(_randomBase, dist.totalChance);

    // Select a single reward based on the roll
    for (uint256 i = 0; i < dist.itemRarities.length; i++) {
      if (roll < dist.itemChances[i]) {
        (_randomBase, mintedId, mintedCollection) = rarityItemMinter.mintRandom(
          dist.itemRarities[i],
          _randomBase,
          _receiver
        );
        rewards[0] = DispensedReward(
          RewardTokenType.ERC1155,
          mintedCollection,
          mintedId,
          1
        );
        break;
      }
      roll -= dist.itemChances[i];
    }

    return DispensedRewards(_randomBase, rewards);
  }

  //=======================================
  // Admin
  //=======================================
  function configureSubPool(
    uint64 _subPool,
    uint16[] calldata _itemRarities,
    uint256[] calldata _itemChances
  ) external onlyAdmin {
    uint256 totalChance = 0;
    for (uint256 i = 0; i < _itemRarities.length; i++) {
      totalChance += _itemChances[i];
    }
    RarityItemRewardsDistribution memory dist = RarityItemRewardsDistribution(
      _itemRarities,
      _itemChances,
      totalChance
    );
    rewardDistributions[_subPool] = dist;
  }

  function updateMinter(address _minter) external onlyAdmin {
    rarityItemMinter = IRarityItemMinter(_minter);
  }

  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

