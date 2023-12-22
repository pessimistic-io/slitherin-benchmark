// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IERC1155.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./IRarityItemMinter.sol";
import "./ManagerModifier.sol";
import "./Random.sol";
import "./IRewardsPool.sol";
import "./IMasterOfInflation.sol";
import "./IPoolConfigProvider.sol";

contract MasterOfInflationLootBoxRewardsPool is
  IRewardsPool,
  ReentrancyGuard,
  Pausable,
  ManagerModifier,
  IPoolConfigProvider
{
  //=======================================
  // Interfaces
  //=======================================
  IMasterOfInflation public masterOfInflation;
  IRewardsPool public backupRewardsPool;

  //=======================================
  // Addresses
  //=======================================
  address public masterOfInflationTokenAddress;

  //=======================================
  // Constants
  //=======================================
  uint256 public masterOfInflationVariableRateConfig;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint64 => uint256) public dropRateCap;
  mapping(uint64 => uint64) public masterOfInflationPool;
  mapping(uint64 => uint64) public masterOfInflationMintAmount;
  mapping(uint64 => uint256[]) public masterOfInflationItemIds;

  //=======================================
  // Events
  //=======================================
  event MasterOfInflationIntegrationFailed(
    uint64 subPoolId,
    address receiver,
    uint256 roll
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _masterOfInflation,
    address _masterOfInflationTokenAddress,
    address _backupRewardsPool
  ) ManagerModifier(_manager) {
    masterOfInflation = IMasterOfInflation(_masterOfInflation);
    masterOfInflationTokenAddress = _masterOfInflationTokenAddress;
    backupRewardsPool = IRewardsPool(_backupRewardsPool);
  }

  // This function returns the chance of receiving a reward from Master of Inflation contract
  function rewardChance(uint64 _subPoolId) external view returns (uint256) {
    uint256 moiChance = masterOfInflation.chanceOfItemFromPool(
      masterOfInflationPool[_subPoolId],
      masterOfInflationMintAmount[_subPoolId],
      0,
      0
    );
    return
      dropRateCap[_subPoolId] < moiChance ? dropRateCap[_subPoolId] : moiChance;
  }

  // Dispenses rewards based on a random roll. Falls back to another reward pool if necessary.
  function dispenseRewards(
    uint64 _subPoolId,
    uint256 _randomBase,
    address _receiver
  ) external onlyManager whenNotPaused returns (DispensedRewards memory) {
    (uint256 roll, uint256 nextBase) = Random.getNextRandom(
      _randomBase,
      ONE_HUNDRED
    );

    bool mintedRewards = false;
    // If the roll is below the drop rate cap, attempt to mint a reward from the master of inflation pool.
    if (roll < dropRateCap[_subPoolId]) {
      uint256 itemId = masterOfInflationItemIds[_subPoolId][
        roll % masterOfInflationItemIds[_subPoolId].length
      ];

      try
        masterOfInflation.tryMintFromPool(
          MintFromPoolParams(
            masterOfInflationPool[_subPoolId], // poolId
            masterOfInflationMintAmount[_subPoolId], // mint amount
            0, // bonus
            itemId, // random item id
            roll, // random number
            _receiver, // recipient
            0 // negative bonus
          )
        )
      returns (bool success) {
        mintedRewards = success;
      } catch {
        emit MasterOfInflationIntegrationFailed(_subPoolId, _receiver, roll);
      }

      // If successfully minted rewards, return the dispensed rewards and the next base for randomization.
      if (mintedRewards) {
        DispensedReward[] memory dispensedRewards = new DispensedReward[](1);
        dispensedRewards[0] = DispensedReward(
          RewardTokenType.ERC1155,
          masterOfInflationTokenAddress,
          itemId,
          masterOfInflationMintAmount[_subPoolId]
        );
        return DispensedRewards(nextBase, dispensedRewards);
      }
    }

    // If the minting from the master of inflation pool fails or the roll is above the drop rate cap, use the backup rewards pool if present.
    if (address(backupRewardsPool) != address(0)) {
      return backupRewardsPool.dispenseRewards(_subPoolId, nextBase, _receiver);
    }

    // If everything failed we just return 0 rewards
    return DispensedRewards(nextBase, new DispensedReward[](0));
  }

  // Configures the addresses of the master of inflation contract,
  // the master of inflation token address, and the backup rewards pool.
  function configureContracts(
    address _masterOfInflation,
    address _masterOfInflationTokenAddress,
    address _backupRewards
  ) external onlyAdmin {
    masterOfInflation = IMasterOfInflation(_masterOfInflation);
    masterOfInflationTokenAddress = _masterOfInflationTokenAddress;
    backupRewardsPool = IRewardsPool(_backupRewards);
  }

  // Configures the parameters of a sub-pool,
  // including drop rate cap, master of inflation pool, mint amount, and item IDs.
  function configureSubPool(
    uint64 _subPoolId,
    uint256 _dropRateCap,
    uint64 _masterOfInflationPool,
    uint64 _amount,
    uint256[] memory itemIds
  ) external onlyAdmin {
    dropRateCap[_subPoolId] = _dropRateCap;
    masterOfInflationPool[_subPoolId] = _masterOfInflationPool;
    masterOfInflationMintAmount[_subPoolId] = _amount;
    masterOfInflationItemIds[_subPoolId] = itemIds;
  }

  function configureVariableRate(
    uint256 _variableRate
  ) external onlyAdmin {
    masterOfInflationVariableRateConfig = _variableRate;
  }

  function getN(uint64 _poolId) external view returns (uint256) {
    return masterOfInflationVariableRateConfig;
  }


  //=======================================
  // Admin
  //=======================================
  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }
}

