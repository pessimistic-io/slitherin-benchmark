// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./QuestType.sol";

/// @dev Farmland - Explorer Stats Smart Contract
contract ExplorerStats is QuestType {

// CONSTRUCTOR

    constructor (
        address[6] memory farmlandAddresses
        ) QuestType (farmlandAddresses) {}

// VIEWS

    /// @dev Return a explorers speed modifier
    /// @dev The speed of each the quest varies based on explorers speed
    /// @param tokenID Explorers ID
    /// @param baseDuration Duration of a single quest in blocks before stat modifier
    function getExplorersQuestDuration(uint256 tokenID, uint256 baseDuration)
        public
        view
        returns (
            uint256 explorersQuestDuration
        )
    {
        // Retrieve Explorer stats
        (,,uint256 speed,,,,,,) = explorers.getStats(tokenID);
        if ( speed < 99) {
            // Calculate how many additional blocks to add to duration based on speed stat
             explorersQuestDuration = (((99 - speed) * baseDuration) / 100);
        }
        return (explorersQuestDuration + baseDuration);
    }

    /// @dev Return a explorers max number of quests
    /// @dev The number of quests a explorer can go on, is based on the explorers stamina.
    /// @dev With a stamina of 99 stamina, you can go on 19 quests per tx
    /// @dev Whereas with stamina of 20, you can go on a max 12 quests per tx
    /// @param tokenID Explorers ID
    /// @param baseMaxNumberOfQuests Maximum number of quests before explorer stat modifier
    function getExplorersMaxQuests(uint256 tokenID, uint256 baseMaxNumberOfQuests)
        public
        view
        returns (
            uint256 maxQuests
        )
    {
        // Retrieve Explorer stats
        (uint256 stamina,,,,,,,,) = explorers.getStats(tokenID);
        // Calculate how many additional quests
        maxQuests = baseMaxNumberOfQuests + (baseMaxNumberOfQuests * stamina / 100);
    }

    /// @dev Return a explorers strength
    /// @param tokenID Explorers ID
    function getExplorersStrength(uint256 tokenID)
        public
        view
        returns (
            uint256 strength
        )
    {
        // Retrieve Explorer stats
        (,strength,,,,,,,) = explorers.getStats(tokenID);
        // Boost for warriors
        if (strength > 95) {
            strength += strength / 2;
        }
    }
 
    /// @dev Return a explorers XP
    /// @param tokenID Explorers ID
    function getExplorersLevel(uint256 tokenID)
        public
        view
        returns (
            uint256 level
        )
    {
        return explorers.getLevel(tokenID);
    }

    /// @dev Return a explorers XP
    /// @param tokenID Explorers ID
    function getExplorersMorale(uint256 tokenID)
        public
        view
        returns (
            uint256 morale
        )
    {
        (,,,,,,morale,,) = explorers.getStats(tokenID);
    }

    /// @dev Return a characters current health
    /// @dev Health regenerates whilst a Character is resting (i.e., not on a activity)
    /// @dev character regains 1 stat per activity duration for that character 
    /// @dev so the speedier the character the quicker to regenerate
    /// @param tokenID Characters ID
    function calculateHealth(uint256 tokenID)
        public
        view
        returns (
            uint256 health
        )
    {
        // Get the Quest ID
        uint256 questID = latestQuest[tokenID];
        // Get the configured reduction rate for health
        uint256 healthReductionRate = quests[questID].healthReductionRate;
        // Get the character activity details
        (bool active, uint256 numberOfActivities, uint256 activityDuration, uint256 startBlock, uint256 endBlock, uint256 completedBlock) = explorers.charactersActivity(tokenID);
        // Get characters max health
        uint256 maxHealth = explorers.getMaxHealth(tokenID);
        // If there's been no activity return max health
        if (endBlock == 0) {return maxHealth;}
        // Get characters health
        (,,,,,health,,,) = explorers.getStats(tokenID);
        // If activity not ended
        if (block.number <= endBlock) {
            // Calculate blocks since activity started
            uint256 blockSinceStartOfActivity = block.number - startBlock;
            // Reduce health used = # of blocks since start of activity / # of Blocks to consume One Health stat
            health -= (blockSinceStartOfActivity / (healthReductionRate * activityDuration));
        } else {
            // If ended but still active i.e., not completed
            if (active) {
                // Reduce health by number of activities
                health -= numberOfActivities;
            } else {
                // Calculate blocks since last activity finished
                uint256 blockSinceLastActivity = block.number - completedBlock;
                // Add health + health regenerated = # of blocks since last activity / # of Blocks To Regenerate One Health stat
                health += (blockSinceLastActivity / activityDuration);
                // Ensure new energy amount doesn't exceed max health
                if (health > maxHealth) {return maxHealth;}
            }
       }
    }

    /// @dev Return the number of blocks until a characters health will regenerate
    /// @param tokenID Characters ID
    function getBlocksToMaxHealth(uint256 tokenID)
        external
        view
        returns (
            uint256 blocks
        )
    {
         // Get the character activity details
        (bool active,, uint256 activityDuration,,, uint256 completedBlock) = explorers.charactersActivity(tokenID);
        // Get characters health
        (,,,,,uint256 health,,,) = explorers.getStats(tokenID);
        // Character not on a activity
        if (!active) {
            // Calculate blocks until health is restored
            uint256 blocksToMaxHealth = completedBlock +(activityDuration * (explorers.getMaxHealth(tokenID)- health));
            if (blocksToMaxHealth > block.number) {
                return blocksToMaxHealth - block.number;
            }
        }
    }

// ADMIN FUNCTIONS

    // Start or pause the sale
    function isPaused(bool value) 
        external
        onlyOwner 
    {
        if ( !value ) {
            _unpause();
        } else {
            _pause();
        }
    }

}
