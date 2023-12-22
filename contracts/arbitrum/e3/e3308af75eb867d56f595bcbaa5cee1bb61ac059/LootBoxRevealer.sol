// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ManagerModifier.sol";
import "./RarityItemConstants.sol";
import "./ILootBox.sol";
import "./ILootBoxDataStorage.sol";
import "./ILootBoxDispenser.sol";
import "./ILootBoxRevealer.sol";
import "./Random.sol";
import "./IRewardsPool.sol";

contract LootBoxRevealer is
  ILootBoxRevealer,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  struct RewardsUnwrapper {
    uint256[] rewardTokenTypes;
    address[] rewardTokenAddresses;
    uint256[] rewardTokenIds;
    uint256[] rewardAmounts;
  }

  //=======================================
  // References
  //=======================================
  ILootBox public lootBox;
  ILootBoxDataStorage public lootBoxDataStorage;
  IRewardsPool public lootBoxRewardsPool;

  //=======================================
  // Uints
  //=======================================
  uint256 public lootBoxesRevealed;
  uint256 minimumGas;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _lootBox,
    address _lootBoxDataStorage,
    address _lootBoxRewardsPool
  ) ManagerModifier(_manager) {
    lootBox = ILootBox(_lootBox);
    lootBoxDataStorage = ILootBoxDataStorage(_lootBoxDataStorage);
    lootBoxRewardsPool = IRewardsPool(_lootBoxRewardsPool);
    minimumGas = 500000;
  }

  //=======================================
  // External
  //=======================================
  function reveal(
    uint256[] calldata _lootBoxTokenIds,
    uint256[] calldata _lootBoxAmounts
  ) external nonReentrant whenNotPaused {
    // Make sure the reveal is not done through another contract
    require(
      msg.sender == tx.origin,
      "Revealing is not allowed through another contract"
    );

    // Burn the LootBoxes
    lootBox.safeBurnBatch(msg.sender, _lootBoxTokenIds, _lootBoxAmounts);

    // Generate additional randomness based on the number of LootBoxes revealed
    uint256 tempLootBoxesRevealed = lootBoxesRevealed;
    uint256 randomBase = Random.startRandomBase(
      tempLootBoxesRevealed,
      uint256(uint160(msg.sender))
    );

    RewardsUnwrapper memory holder;
    for (uint256 i = 0; i < _lootBoxTokenIds.length; i++) {
      // Get the rarity of the burned LootBox
      uint16 lootBoxRarity = uint16(
        lootBoxDataStorage.characteristics(
          _lootBoxTokenIds[i],
          ITEM_CHARACTERISTIC_RARITY
        )
      );

      // Dispense rewards for each Lootbox
      for (uint256 j = 0; j < _lootBoxAmounts[i]; j++) {
        require(gasleft() > minimumGas, "Manual gas reduction is not allowed");

        DispensedRewards memory result = lootBoxRewardsPool.dispenseRewards(
          lootBoxRarity,
          randomBase,
          msg.sender
        );

        // Use the remainder of the hash as the random base for other Lootboxes
        randomBase = result.nextRandomBase;

        // Emit acquired rewards as an event for each Lootbox
        holder.rewardTokenTypes = new uint256[](result.rewards.length);
        holder.rewardTokenAddresses = new address[](result.rewards.length);
        holder.rewardTokenIds = new uint256[](result.rewards.length);
        holder.rewardAmounts = new uint256[](result.rewards.length);

        for (uint r = 0; r < result.rewards.length; r++) {
          DispensedReward memory reward = result.rewards[r];
          holder.rewardTokenTypes[r] = (uint256)(reward.tokenType);
          holder.rewardTokenAddresses[r] = reward.token;
          holder.rewardTokenIds[r] = reward.tokenId;
          holder.rewardAmounts[r] = reward.amount;
        }

        emit LootBoxRevealedEvent(
          tempLootBoxesRevealed++,
          msg.sender,
          _lootBoxTokenIds[i],
          holder.rewardTokenTypes,
          holder.rewardTokenAddresses,
          holder.rewardTokenIds,
          holder.rewardAmounts
        );
      }

      // Increase the amount of LootBoxes revealed by the sender
      lootBoxesRevealed = tempLootBoxesRevealed;
    }
  }

  //=======================================
  // Admin
  //=======================================

  // Set minimum gas required (per lootbox)
  function setMinimumGas(uint256 _minimumGas) external onlyAdmin {
    minimumGas = _minimumGas;
  }

  function setRewardPool(address _rewardPoolAddress) external onlyAdmin {
    lootBoxRewardsPool = IRewardsPool(_rewardPoolAddress);
  }

  // Pauses the contract in case of emergency
  function pause() external onlyAdmin {
    _pause();
  }

  // Unpauses the contract
  function unpause() external onlyAdmin {
    _unpause();
  }
}

