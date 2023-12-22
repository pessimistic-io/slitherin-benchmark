// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Quest { 
    string name;                                    // The name of the quest
    uint256[5] dropRate;                            // The percentage chance of getting items [common % ,uncommon %, rare %, epic %, legendary %]
    uint256 itemSet;                                // The list of useful items & rewards in the quest
    uint256 questPrice;                             // Price of the quest, to be burned if payment address is empty
    uint256 chanceOfFindingLand;                    // Base chance of finding Land before item boosts
    address paymentAddress;                         // Zero address is a free mint
    uint256 questDuration;                          // Duration of a single quest in blocks
    uint256 maxNumberOfActivitiesBase;              // Maximum number of activities before explorer boosts
    uint256 hazardDifficultyCap;                    // If hazard difficulty > 0, then enabled. The higher the difficultly the harder the quest
    uint256 moraleReductionRate;                    // Determines the amount that Morale reduces per quest. 0 indicates that morale doesn't reduce
    uint256 healthReductionRate;                    // Determines the amount that Health reduces per quest. 0 indicates that morale doesn't reduce
    uint256 xpEmmissionRate;                        // Determines the amount of XP emitted per quest
    uint256 minimumLevel;                           // Sets a minimum level to start this quest
    bool active;                                    // Status (Active/Inactive)
    }

struct Inventory {uint256 itemID; uint256 amount;}

/**
 * @dev Farmland - Quests Interface
 */
interface IQuests {

// SETTERS
    function addExplorer(uint256 tokenID) external;
    function releaseExplorer(uint256 index) external;
    function beginQuest(uint256 questID, uint256 tokenID, uint256 numberOfQuests, uint256 itemID) external;
    function completeQuest(uint256 tokenID) external;
    function endQuest(uint256 tokenID, bool includeItem, uint256 itemID) external;
    function abortQuest(uint256 tokenID) external;

// GETTERS
    function getQuests() external view returns (string[] memory allQuests);
    function getQuestDropRates(uint256 questID) external view returns (uint256[5] memory dropRate);
    function getItemsByExplorer(uint256 tokenID, address account) external view returns (Inventory[] memory items);
    function calculateHealth(uint256 tokenID) external  view returns (uint256 health);
    function getMaxHealth(uint256 tokenID) external  view returns (uint256 health);
}
