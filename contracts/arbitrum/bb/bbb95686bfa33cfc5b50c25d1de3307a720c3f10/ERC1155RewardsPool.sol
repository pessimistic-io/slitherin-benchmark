// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC1155.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";

contract ERC1155RewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Interfaces
  //=======================================
  IERC1155 public externalCollection;
  IRewardsPool public backupPool;

  //=======================================
  // Addresses
  //=======================================
  address public externalCollectionBankAddress;

  //=======================================
  // Enums
  //=======================================
  enum DepletedFallbackType {
    USE_BACKUP_POOL,
    DISPENSE_NEXT_AVAILABLE,
    DROP_REWARD
  }

  //=======================================
  // Structs
  //=======================================
  struct ERC1155RewardsDistribution {
    uint256[] itemIds;
    uint256[] itemAmounts;
    uint256[] itemChances;
    uint256 totalChance;
    DepletedFallbackType fallbackType;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint64 => ERC1155RewardsDistribution) public rewardDistributions;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _collection,
    address _bank
  ) ManagerModifier(_manager) {
    externalCollection = IERC1155(_collection);
    externalCollectionBankAddress = _bank;
    backupPool = IRewardsPool(address(0));
  }

  //=======================================
  // External
  //=======================================
  // Dispense token rewards to the receiver based on the sub-pool ID and random number
  function dispenseRewards(
    uint64 _subPoolId,
    uint256 _randomBase,
    address _receiver
  ) external onlyManager whenNotPaused returns (DispensedRewards memory) {
    ERC1155RewardsDistribution storage dist = rewardDistributions[_subPoolId];

    DispensedReward[] memory rewards = new DispensedReward[](1);
    (uint256 roll, uint256 nextBase) = Random.getNextRandom(
      _randomBase,
      dist.totalChance
    );

    // We iterate through the array twice in case there are not enough of one of the tokens in the pool (for DISPENSE_NEXT_AVAILABLE fallback).
    for (uint256 i = 0; i < dist.itemIds.length * 2; i++) {
      uint256 tokenIndex = i % dist.itemIds.length;
      if (roll < dist.itemChances[tokenIndex]) {
        // If there is enough balance in the bank, transfer the reward to the receiver
        if (
          externalCollection.balanceOf(
            externalCollectionBankAddress,
            dist.itemIds[tokenIndex]
          ) >= dist.itemAmounts[tokenIndex]
          && externalCollection.isApprovedForAll(externalCollectionBankAddress, address(this))
        ) {
          try externalCollection.safeTransferFrom(
            externalCollectionBankAddress,
            _receiver,
            dist.itemIds[tokenIndex],
            dist.itemAmounts[tokenIndex],
            ""
          ) {
            rewards[0] = DispensedReward(
              RewardTokenType.ERC1155,
              address(externalCollection),
              dist.itemIds[tokenIndex],
              dist.itemAmounts[tokenIndex]
            );
          } catch {
            rewards = new DispensedReward[](0);
          }

          return DispensedRewards(nextBase, rewards);
        }
        // Fallback Config 1: Use backup pool
        else if (dist.fallbackType == DepletedFallbackType.USE_BACKUP_POOL) {
          require(
            address(backupPool) != address(0),
            "Backup rewards pool not configured"
          );
          return backupPool.dispenseRewards(_subPoolId, _randomBase, _receiver);
          // Fallback Config 2: Do not dispense if out of stock
        } else if (dist.fallbackType == DepletedFallbackType.DROP_REWARD) {
          return DispensedRewards(nextBase, new DispensedReward[](0));
        }
      }

      // Fallback Config 3: We'll continue iterating and dispense the next token on the list
      // This is good method if all tokens are of equal value
      if (roll < dist.itemChances[tokenIndex]) {
        roll = 0;
      } else {
        roll -= dist.itemChances[tokenIndex];
      }
    }

    // If the rewards pool is empty, use the backup pool to dispense rewards
    if (address(backupPool) != address(0)) {
      return backupPool.dispenseRewards(_subPoolId, _randomBase, _receiver);
    }

    // If the rewards pool is empty, and there is no backup pool we return 0 rewards
    return DispensedRewards(nextBase, new DispensedReward[](0));
  }

  //=======================================
  // Admin
  //=======================================
  function configureContracts(
    address _collection,
    address _bank,
    address _backupPool
  ) external onlyAdmin {
    externalCollection = IERC1155(_collection);
    externalCollectionBankAddress = _bank;
    backupPool = IRewardsPool(_backupPool);
  }

  function configureSubPool(
    uint64 _subPoolId,
    uint256[] calldata _itemAmounts,
    uint256[] calldata _itemIds,
    uint256[] calldata _itemChances,
    DepletedFallbackType _fallback
  ) external onlyAdmin {
    require(_itemAmounts.length == _itemIds.length);
    require(_itemAmounts.length == _itemChances.length);

    uint256 totalChance = 0;
    for (uint256 i = 0; i < _itemIds.length; i++) {
      totalChance += _itemChances[i];
    }

    ERC1155RewardsDistribution memory dist = ERC1155RewardsDistribution(
      _itemIds,
      _itemAmounts,
      _itemChances,
      totalChance,
      _fallback
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

