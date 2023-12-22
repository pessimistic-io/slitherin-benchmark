// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC721A.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

contract ERC721RewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  event ERC721VaultDepleted(
    uint64 subPool,
    uint256 subPoolIndex,
    address token,
    address receiver
  );

  //=======================================
  // Addresses
  //=======================================
  address public vaultAddress;

  //=======================================
  // Enums
  //=======================================
  enum DepletedFallbackType {
    DISPENSE_NEXT_AVAILABLE,
    DROP_REWARD
  }

  //=======================================
  // Structs
  //=======================================
  struct ERC721RewardsDistribution {
    uint256[] itemChances;
    uint256[][] tokenIds;
    address[] externalCollections;
    uint256[] nextTokenIndex;
    uint256 totalChance;
    DepletedFallbackType fallbackType;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint64 => ERC721RewardsDistribution) public rewardDistributions;

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, address _vault) ManagerModifier(_manager) {
    vaultAddress = _vault;
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
    ERC721RewardsDistribution storage dist = rewardDistributions[_subPoolId];
    require(dist.totalChance > 0, "ERC721RewardsPool: not configured");

    (uint256 roll, uint256 nextBase) = Random.getNextRandom(
      _randomBase,
      dist.totalChance
    );

    // We iterate through the array twice in case there are not enough of one of the tokens in the pool (for DISPENSE_NEXT_AVAILABLE fallback).
    for (uint256 i = 0; i < dist.itemChances.length * 2; i++) {
      uint256 tokenIndex = i % dist.itemChances.length;
      bool won = roll < dist.itemChances[tokenIndex];

      if (roll < dist.itemChances[tokenIndex]) {
        roll = 0;
      } else {
        roll -= dist.itemChances[tokenIndex];
      }

      if (won) {
        // Check if the rewards pool is depleted, either stop here or continue to the next reward
        if (
          dist.nextTokenIndex[tokenIndex] >= dist.tokenIds[tokenIndex].length
        ) {
          if (
            dist.fallbackType == DepletedFallbackType.DISPENSE_NEXT_AVAILABLE
          ) {
            continue;
          } else {
            break;
          }
        }

        // Get next tokenId to transfer
        uint256 tokenId = dist.tokenIds[tokenIndex][
          dist.nextTokenIndex[tokenIndex]++
        ];
        DispensedReward[] memory rewards = new DispensedReward[](1);
        IERC721A collection = IERC721A(dist.externalCollections[tokenIndex]);

        // Check if the token is still approved in the vault, if not - either stop here or continue to the next reward
        if (collection.ownerOf(tokenId) != vaultAddress || !collection.isApprovedForAll(vaultAddress, address(this))) {
          if (
            dist.fallbackType == DepletedFallbackType.DISPENSE_NEXT_AVAILABLE
          ) {
            continue;
          } else {
            break;
          }
        }

        try collection.safeTransferFrom(vaultAddress, _receiver, tokenId) {
          rewards[0] = DispensedReward(
            RewardTokenType.ERC721,
            address(collection),
            tokenId,
            1
          );
        } catch {
          emit ERC721VaultDepleted(_subPoolId, tokenIndex-1, address(collection), _receiver);
          rewards = new DispensedReward[](0);
        }
        return DispensedRewards(nextBase, rewards);
      }
    }

    emit ERC721VaultDepleted(_subPoolId, 0, address(0), _receiver);
    // If the rewards pool is empty we return 0 rewards
    return DispensedRewards(nextBase, new DispensedReward[](0));
  }

  //=======================================
  // Admin
  //=======================================
  function configureVault(address _vault) external onlyAdmin {
    vaultAddress = _vault;
  }

  function configureSubPool(
    uint64 _subPoolId,
    uint256[] calldata _itemChances,
    uint256[][] calldata _tokenIds,
    uint256[] calldata _nextTokenIndexes,
    address[] calldata _erc721Addresses,
    DepletedFallbackType _fallbackType
  ) external onlyAdmin {
    require(_itemChances.length == _nextTokenIndexes.length);
    require(_itemChances.length == _tokenIds.length);
    require(_itemChances.length == _erc721Addresses.length);

    uint256 totalChance = 0;
    for (uint256 i = 0; i < _tokenIds.length; i++) {
      totalChance += _itemChances[i];
    }

    rewardDistributions[_subPoolId] = ERC721RewardsDistribution(
      _itemChances,
      _tokenIds,
      _erc721Addresses,
      _nextTokenIndexes,
      totalChance,
      _fallbackType
    );
  }

  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

