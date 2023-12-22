// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPetroRewardManager {
   

   function createNodeType(uint256 _type, uint256 _durability,uint256 _storage, uint256 _rewards,uint256 _reductionClog,uint256 _levelUpPrice,uint256 _repairPrice,uint256 _storageRateLevelUp,uint256 _rewardRateLevelUp,uint256 _durabilityRateLevelUp) external;
   function applyBoostToExistingNodeOfPlot(uint256 _plotID, uint256 _boost) external;

}

