// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.7.0;
pragma experimental ABIEncoderV2;

enum CollectibleType {Farmer, Tractor, Equipment}
struct Farm {uint256 amount; uint256 compostedAmount; uint256 blockNumber; uint256 lastHarvestedBlockNumber; address harvesterAddress; uint256 numberOfCollectibles;}
struct Collectible {uint256 id; CollectibleType collectibleType; uint256 maxBoostLevel; uint256 addedBlockNumber; uint256 expiry; string uri;}

/**
 * @dev Farmland - Crop V2 Interface
 */
interface ICropV2 {

// SETTERS
    function allocate(address farmAddress, uint256 amount) external;
    function release() external;
    function compost(address farmAddress, uint256 amount) external;
    function harvest(address farmAddress, address targetAddress, uint256 targetBlock) external;
    function directCompost(address farmAddress, uint256 targetBlock) external;
    function equipCollectible(uint256 tokenID, CollectibleType collectibleType) external;
    function releaseCollectible(uint256 index) external;
    function isPaused(bool value) external;
    function setFarmlandVariables(uint256 endMaturityBoost_, uint256 maxGrowthCycle_, uint256 maxGrowthCycleWithFarmer_, uint256 maxCompostBoost_, uint256 maxMaturityBoost_, uint256 maxMaturityCollectibleBoost_,uint256 maxFarmSizeWithoutFarmer_,uint256 maxFarmSizeWithoutTractor_, uint256 bonusCompostBoostWithFarmer_, uint256 bonusCompostBoostWithTractor_) external;
    function setFarmlandAddresses(address landAddress_, address payable farmerNFTAddress_, address payable tractorNFTAddress_) external;

// GETTERS
    function getHarvestAmount(address farmAddress, uint256 targetBlock) external view returns (uint256 availableToHarvest);
    function getFarmCompostBoost(address farmAddress) external view returns (uint256 compostBoost);
    function getFarmMaturityBoost(address farmAddress) external view returns (uint256 maturityBoost);
    function getTotalBoost(address farmAddress) external view returns (uint256 totalBoost);
    function getCompostBonus(address farmAddress, uint256 amount) external view returns (uint256 compostBonus);
    function getNFTAddress(CollectibleType collectibleType) external view returns (address payable collectibleAddress);
    function getFarmCollectibleTotals(address farmAddress) external view returns (uint256 totalMaxBoost, uint256 lastAddedBlockNumber);
    function getFarmCollectibleTotalOfType(address farmAddress, CollectibleType collectibleType) external view returns (uint256 ownsCollectibleTotal);
    function getCollectiblesByFarm(address farmAddress) external view returns (Collectible[] memory farmCollectibles);
    function getAddressRatio(address farmAddress) external view returns (uint256 myRatio);
    function getGlobalRatio() external view returns (uint256 globalRatio);
    function getGlobalAverageRatio() external view returns (uint256 globalAverageRatio);
    function getAddressDetails(address farmAddress) external view returns (uint256 blockNumber, uint256 cropBalance, uint256 cropAvailableToHarvest, uint256 farmMaturityBoost, uint256 farmCompostBoost, uint256 farmTotalBoost);
    function getAddressTokenDetails(address farmAddress) external view returns (uint256 blockNumber, bool isOperatorLand, uint256 landBalance, uint256 myRatio, bool isOperatorFarmer, bool isOperatorEquipment, bool isOperatorTractor);
    function getFarmlandVariables() external view returns (uint256 totalFarms, uint256 totalAllocatedAmount, uint256 totalCompostedAmount,uint256 maximumCompostBoost, uint256 maximumMaturityBoost, uint256 maximumGrowthCycle, uint256 maximumGrowthCycleWithFarmer, uint256 maximumMaturityCollectibleBoost, uint256 endMaturityBoostBlocks, uint256 maximumFarmSizeWithoutFarmer, uint256 maximumFarmSizeWithoutTractor, uint256 bonusCompostBoostWithAFarmer, uint256 bonusCompostBoostWithATractor);
    function getFarmlandAddresses() external view returns (address, address, address, address, address);
}

