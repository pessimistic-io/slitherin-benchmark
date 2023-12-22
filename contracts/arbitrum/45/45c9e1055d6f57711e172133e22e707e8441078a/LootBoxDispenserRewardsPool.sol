// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Strings.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./ILootBoxDispenser.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";

// Handles the rewards pool for paying homage.
// It utilizes the LootBoxDispenser contract to mint and dispense rewards based on predefined chances for each tokenId.
contract LootBoxDispenserRewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Interfaces
  //=======================================
  ILootBoxDispenser public LOOTBOX_DISPENSER;

  //=======================================
  // Structs
  //=======================================
  struct LootBoxRewardsDistribution {
    uint256[] tokenIds;
    uint256[] chances;
    uint256[] amounts;
    uint256 totalChance;
  }

  //=======================================
  // Addresses
  //=======================================
  address public LOOTBOX;

  mapping(uint64 => LootBoxRewardsDistribution) public rewardDistributions;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _lootBoxDispenser,
    address _lootBox
  ) ManagerModifier(_manager) {
    LOOTBOX_DISPENSER = ILootBoxDispenser(_lootBoxDispenser);
    LOOTBOX = _lootBox;
  }

  //=======================================
  // External
  //=======================================
  function dispenseRewards(
    uint64 _subPoolId,
    uint256 _randomBase,
    address _receiver
  ) external onlyManager whenNotPaused returns (DispensedRewards memory) {
    LootBoxRewardsDistribution storage dist = rewardDistributions[_subPoolId];
    require(dist.totalChance > 0, Strings.toString(_subPoolId));

    uint256 roll;
    DispensedReward[] memory rewards = new DispensedReward[](1);
    (roll, _randomBase) = Random.getNextRandom(_randomBase, dist.totalChance);

    // Select a single reward based on the roll
    for (uint256 i = 0; i < dist.tokenIds.length; i++) {
      if (roll < dist.chances[i]) {
        LOOTBOX_DISPENSER.dispense(
          _receiver,
          dist.tokenIds[i],
          dist.amounts[i]
        );
        rewards[0] = DispensedReward(
          RewardTokenType.ERC1155,
          LOOTBOX,
          dist.tokenIds[i],
          dist.amounts[i]
        );
        break;
      }
      roll -= dist.chances[i];
    }

    return DispensedRewards(_randomBase, rewards);
  }

  //=======================================
  // Admin
  //=======================================
  // Set chances for each item rarity in a subpool.
  function configureSubPool(
    uint64 _subPool,
    uint256[] calldata _tokenIds,
    uint256[] calldata _chances,
    uint256[] calldata _amounts
  ) external onlyAdmin {
    uint256 totalChance = 0;
    for (uint256 i = 0; i < _tokenIds.length; i++) {
      totalChance += _chances[i];
    }
    LootBoxRewardsDistribution memory dist = LootBoxRewardsDistribution(
      _tokenIds,
      _chances,
      _amounts,
      totalChance
    );
    rewardDistributions[_subPool] = dist;
  }

  function updateDispenser(address _dispenser) external onlyAdmin {
    LOOTBOX_DISPENSER = ILootBoxDispenser(_dispenser);
  }

  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

