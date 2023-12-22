// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ExplorerStats.sol";

/// @dev Farmland - Quests Smart Contract
contract Quests is ExplorerStats {

// CONSTRUCTOR

    constructor(
        address[6] memory farmlandAddresses
        ) ExplorerStats (farmlandAddresses)
    {
        require(farmlandAddresses.length == 6,      "Invalid number of contract addresses");
        require(farmlandAddresses[0] != address(0), "Invalid Corn Contract address");
        require(farmlandAddresses[1] != address(0), "Invalid Character Contract address");
        require(farmlandAddresses[2] != address(0), "Invalid Land Distributor Contract address");
        require(farmlandAddresses[3] != address(0), "Invalid Items Contract address");
        require(farmlandAddresses[4] != address(0), "Invalid Item Sets address");
        require(farmlandAddresses[5] != address(0), "Invalid Land Contract address");
    }

// EVENTS

    event QuestStarted(address indexed account, uint256 quest, uint256 endblockNumber, uint256 indexed tokenID);
    event QuestCompleted(address indexed account, uint256 quest, uint256 endblockNumber, uint256 indexed tokenID);
    event QuestAborted(address indexed account, uint256 quest, uint256 endblockNumber, uint256 indexed tokenID);
    event ItemFound(address indexed account, uint256 quest, uint256 indexed tokenID, uint256 itemMinted, uint256 amountMinted, uint256 amountOfLandFound);

// FUNCTIONS
        
    /// @dev Quest for items
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    /// @param numberOfActivities number of quests in a single transaction
    /// @param itemID of item to equip to help complete the quest
    function beginQuest(uint256 questID, uint256 tokenID, uint256 numberOfActivities, uint256 itemID)
        external
        nonReentrant
        onlyInactive(tokenID)
        onlyCharacterOwner(tokenID)
        onlyWhenQuestEnabled(questID)
        whenNotPaused
    {
        // Set the quest ID
        latestQuest[tokenID] = questID;
        //Initialize activity & set variables
        uint256 activityDuration = getExplorersQuestDuration(tokenID, quests[questID].questDuration);
        Activity memory activity = Activity({
            active: true,
            numberOfActivities: numberOfActivities,
            startBlock: block.number,
            activityDuration: getExplorersQuestDuration(tokenID, quests[questID].questDuration),
            endBlock: block.number + (activityDuration * numberOfActivities),
            completedBlock: 0
        });
        // Write an event
        emit QuestStarted(_msgSender(), questID, activity.endBlock, tokenID);
        // If using an item
        if (itemID > 0) {
            // Add item to the explorers inventory
            addItem(tokenID, itemID);
        }
        // Setup hazards if required for quest
        setupHazards(questID, tokenID, numberOfActivities);
        // Update the mercenaries health before starting a new quest
        updateHealth(questID, tokenID, numberOfActivities);
        // Do a few checks
        require(getExplorersLevel(tokenID) >= quests[questID].minimumLevel, "Explorer needs to level up");
        require (numberOfActivities <= getExplorersMaxQuests(tokenID, quests[questID].maxNumberOfActivitiesBase), "Exceeds maximum quest duration");
        // Calculate the amount of Corn required
        uint256 cornAmount = numberOfActivities * quests[questID].questPrice;
        // Burn Corn
        cornContract.operatorBurn(_msgSender(), cornAmount, "", "");
        // Activate Explorer & update the activity details
        explorers.startActivity(tokenID, activity);
    }

    /// @dev Complete the quest
    /// @param tokenID Explorers ID
    function completeQuest(uint256 tokenID)
        external
        nonReentrant
        onlyCharacterOwner(tokenID)
        onlyQuestExpired(tokenID)
        onlyActive(tokenID)
    {
        // Get the Quest ID
        uint256 questID = latestQuest[tokenID];
        // Get the number of activities
        (,uint256 numberOfActivities,,,,) = explorers.charactersActivity(tokenID);
        // Write an event
        emit QuestCompleted(_msgSender(), latestQuest[tokenID], block.number, tokenID);
        // Call mint rewards function
        mintRewards(questID, tokenID, numberOfActivities);
        // Release explorer
        explorers.updateActivityStatus(tokenID, false);
        // Release the item
        releaseItem(tokenID);
        // Decrease the mercenaries morale 
        decreaseMorale(questID, tokenID, numberOfActivities);
        // Decrease the explorers health
        decreaseHealth(questID, tokenID, numberOfActivities);
    }

    /// @dev Abort quest without collecting items
    /// @param tokenID Explorers ID
    function abortQuest(uint256 tokenID)
        external
        nonReentrant
        onlyCharacterOwner(tokenID)
    {        
        // Get the Quest ID
        uint256 questID = latestQuest[tokenID];
        // Get the number of activities
        (,uint256 numberOfActivities,,,,) = explorers.charactersActivity(tokenID);
        // Write an event
        emit QuestAborted(_msgSender(), questID, block.number, tokenID);
        // Release explorer
        explorers.updateActivityStatus(tokenID, false);
        // Release the item
        releaseItem(tokenID);
        // Decrease the mercenaries morale 
        decreaseMorale(questID, tokenID, numberOfActivities);
        // Decrease the explorers health
        decreaseHealth(questID, tokenID, numberOfActivities);
    }

// PRIVATE HELPER FUNCTIONS

    /// @dev Remove an item from a explorers inventory at the end of a quest
    /// @param tokenID Explorers ID
    /// @param itemID Item ID
    function addItem(uint256 tokenID, uint256 itemID)
        private
    {
        require(itemsContract.balanceOf(_msgSender(),itemID) > 0, "Item balance too low");
        // Add item to mapping to indicate it's in use on a quest
        itemOnQuest[tokenID] = itemID;
        // Set the item as in use AKA equip the item
        itemsContract.setItemInUse(_msgSender(), tokenID, itemID, 1, true);
    }

    /// @dev Remove an item from a explorers inventory at the end of a quest
    /// @param tokenID Explorers ID
    function releaseItem(uint256 tokenID)
        private
    {
        // Store the itemID of the active item
        uint256 itemID = itemOnQuest[tokenID];
        // Check if there's an item in use
        if (itemID > 0) {
            // Release the item
            itemsContract.setItemInUse(_msgSender(), tokenID, itemID, 1, false);
        }
    }

    /// @dev Setup Hazards by quest
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    /// @param numberOfActivities on the quest
    function setupHazards(uint256 questID, uint256 tokenID, uint256 numberOfActivities)
        private
    {
        // Store the difficulty cap
        uint256 hazardDifficultyCap = quests[questID].hazardDifficultyCap;
        // If hazards configured for this quest
        if (hazardDifficultyCap > 0) {
            // Loop through the number of activities to check
            for(uint256 i=0; i < numberOfActivities;) {
                // Check if hazard will be avoided for each quest
                currentHazards[tokenID].push(isHazardAvoided(tokenID, hazardDifficultyCap, i));
                unchecked { ++i; }
            }
        }
    }

    /// @dev Update the Explorers health 
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    /// @param numberOfActivities on the quest
    function updateHealth(uint256 questID, uint256 tokenID, uint256 numberOfActivities)
        private
    {
        // Get the configured reduction rate for health
        uint256 healthReductionRate = quests[questID].healthReductionRate;
        if (healthReductionRate > 0) {
            // Calculate & store the current health
            uint256 health = calculateHealth(tokenID);
            explorers.setStatTo(tokenID, health, 5);
            // Check that the Explorer has enough health to complete the quest
            require (health > (numberOfActivities * healthReductionRate), "Explorer needs more health");
        }
    }

    /// @dev Decrease the mercenaries morale 
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    /// @param numberOfActivities on the quest
    function decreaseMorale(uint256 questID, uint256 tokenID, uint256 numberOfActivities)
        private
    {
        // Get the configured reduction rate for morale
        uint256 moraleReductionRate = quests[questID].moraleReductionRate;
        if (moraleReductionRate > 0) {
            // Decrease the mercenaries morale if configured
            explorers.decreaseStat(tokenID, (numberOfActivities * moraleReductionRate), 6);
        }
    }
    
    /// @dev Decrease the mercenaries health 
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    /// @param numberOfActivities on the quest
    function decreaseHealth(uint256 questID, uint256 tokenID, uint256 numberOfActivities)
        private
    {
        // Get the configured reduction rate for health
        uint256 healthReductionRate = quests[questID].healthReductionRate;
        if (healthReductionRate > 0) {
            // Decrease the mercenaries health if configured
            explorers.decreaseStat(tokenID, (numberOfActivities * healthReductionRate), 5);
        }
    }

    /// @dev Mint items found on a quest
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    /// @param numberOfActivities on the quest
    function mintRewards(uint256 questID, uint256 tokenID, uint256 numberOfActivities)
        private
    {
        // Initialise local variables
        uint256 itemToMint = 0;
        uint256 totalToMint = 1;
        uint256 amountOfLandFound = 0;
        uint256 totalHazards = currentHazards[tokenID].length;
        // Loop through the quest and mint items
        for(uint256 i=0; i < numberOfActivities;) {
            // If hazard avoided mints rewards
            if (totalHazards == 0 || currentHazards[tokenID][i]) {
                // Calculate the Land
                amountOfLandFound = getLandAmount(questID, tokenID, i);
                // Calculate the items found
                (itemToMint, totalToMint) = getRewardItem(questID, tokenID, i);
                // If there's Land to send then ensure there is enough Land left in the contract
                if (amountOfLandFound > 0 && landContract.balanceOf(address(landDistributor)) > amountOfLandFound) {
                    // Write an event for each quest
                    emit ItemFound(_msgSender(), questID, tokenID, itemToMint, totalToMint, amountOfLandFound);
                    // Send the found Land
                    landDistributor.issueLand(_msgSender(),amountOfLandFound);
                } else {
                    // Write an event for each quest
                    emit ItemFound(_msgSender(), questID, tokenID, itemToMint, totalToMint, 0);
                }
                // Mint reward items
                itemsContract.mintItem(itemToMint, totalToMint, _msgSender());
            }
            // Increase the explorers XP
            explorers.increaseStat(tokenID, quests[questID].xpEmmissionRate, 7);
            unchecked { ++i; }
        }
        if (totalHazards > 0) {
            // Reset the hazard mapping
            delete currentHazards[tokenID];
        }
    }

// VIEWS

    /// @dev Return a reward item & amount to mint
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    function getRewardItem(uint256 questID, uint256 tokenID, uint256 salt)
        private
        view
        returns (
            uint256 itemToMint,
            uint256 totalToMint
        )
    {
        // Initialise local variable
        uint256 dropRateBucket = 0;
        // Declare & set the pack item set to work from
        uint256 itemSet = quests[questID].itemSet;
        // Get some random numbers
        uint256[] memory randomNumbers = new uint256[](4);
        randomNumbers = getRandomNumbers(4, tokenID * salt);
        // Choose a random number up to 1000
        uint256 random = randomNumbers[0] % 1000;
        // Loop through the array of drop rates
        for (uint256 i = 0; i < 5;) {
            if (random > quests[questID].dropRate[i] &&
                // Choose drop rate & ensure an item is registered
                itemSetsContract.getItemSetByRarity(itemSet, i).length > 0) {
                // Set the drop rate bucket for minting
                dropRateBucket = i;
                // Move on
                break;
            }
            unchecked { ++i; }
        }
        // Retrieve the list of items
        Item[] memory rewardItems = itemSetsContract.getItemSetByRarity(itemSet, dropRateBucket);
        require(rewardItems.length > 0, "ADMIN: Not enough items registered");
        // Randomly choose item to mint
        uint256 itemIndex = randomNumbers[1] % rewardItems.length;
        // Finds the items ID
        itemToMint = rewardItems[itemIndex].itemID;
        // Retrieve Explorers Strength modifier
        uint256 strength = getExplorersStrength(tokenID);
        // Retrieve Items scarcityCap
        uint256 scarcityCap = rewardItems[itemIndex].value1;
        // Ensure that the explorers strength limits the amount of items awarded by
        // checking if the item scarcity cap is greater than the explorers strength
        if (scarcityCap > strength) {
            // Choose a random number capped @ explorers strength
            totalToMint = (randomNumbers[2] % strength);
        } else {
            // Otherwise choose a random number capped @ item scarcity cap
            totalToMint = (randomNumbers[3] % scarcityCap);
        }
        // Ensure at least 1 item is found
        if (totalToMint == 0) { totalToMint = 1;}
    }
    
    /// @dev Checks to see if a hazard has been avoided
    /// @param tokenID Explorers ID
    /// @param hazardDifficultyCap defines the difficulty of the quest
    /// @param salt used to help with randomness
    function isHazardAvoided(uint256 tokenID, uint256 hazardDifficultyCap, uint256 salt)
        private
        view
        returns (bool hazardAvoided)
    {
        uint256[] memory randomNumbers = new uint256[](1);
        // Return a random number
        randomNumbers = getRandomNumbers(1, tokenID * salt);
        // Get the item that's in use
        uint256 itemID = itemOnQuest[tokenID];
        // Check if there's an item in use
        if (itemID > 0) {
            // Get the item modifier variable
            uint256 difficultyMod = getItemModifier(itemID, HAZARD_ITEM_SET);
            // Only apply the modifier if it's greater than zero
            if (difficultyMod > 0) {
                // Recalculate the hazardDifficultyCap by reducing it by the difficulty modifier as a %
                hazardDifficultyCap -= hazardDifficultyCap * difficultyMod / 100;
            }
        }
        // Get the explorers morale
        uint256 morale = getExplorersMorale(tokenID);
        // Assign hazard difficulty up the maximum difficulty cap
        uint256 hazardDifficulty = randomNumbers[0] % hazardDifficultyCap;
        // Morale has to be greater than a random number between 0-hazardDifficultyCap for the explorer to avoid the hazard
        if (morale > hazardDifficulty) {
            // Returns true if the hazard was avoided
            return true;
        }
    }

    /// @dev Return the amount of Land found
    /// @param questID Quest ID
    /// @param tokenID Explorers ID
    function getLandAmount(uint256 questID, uint256 tokenID, uint256 salt)
        private
        view
        returns (
            uint256 amountOfLandFound
        )
    {
        // Get some random numbers
        uint256[] memory randomNumbers = new uint256[](2);
        randomNumbers = getRandomNumbers(2, tokenID * salt);
        // Get the item that's in use
        uint256 itemID = itemOnQuest[tokenID];
        // Check if there's an item in use
        uint256 itemModifier = 0;
        if (itemID > 0) {
            // Get the item modifier variable
            itemModifier = getItemModifier(itemID, LAND_ITEM_SET);
        }
        // Set the default chance of finding Land unless explorer is carrying a land item
        uint256 chanceOfFindingLand;
        if (itemModifier > 0) {
            chanceOfFindingLand = itemModifier;
        } else {
            chanceOfFindingLand = quests[questID].chanceOfFindingLand;
        }
        // Land is found if the random number is less than the chance of finding Land
        if (randomNumbers[0] % 1000 < chanceOfFindingLand) {
            // The explorer found between 1 and max 99 (capped at the explorers of morale)
            amountOfLandFound = ((randomNumbers[1] % getExplorersMorale(tokenID)) +1) * (10**18);
        }
    }

    /// @dev Grab the Item Modifier (value1)
    /// @param itemID Item ID in use
    /// @param itemSet Item set to check
    function getItemModifier(uint256 itemID, uint256 itemSet)
        private
        view
        returns (uint256 value)
    {
        // Retrieve all the useful items of a specified type
        Item[] memory usefulItems = itemSetsContract.getItemSet(itemSet);
        // Loop through the items
        for(uint256 i = 0; i < usefulItems.length;){
            if (itemID == usefulItems[i].itemID) {
                // return the item modifier for this item
                return usefulItems[i].value1;
            }
            unchecked { ++i; }
        }
    }

}
