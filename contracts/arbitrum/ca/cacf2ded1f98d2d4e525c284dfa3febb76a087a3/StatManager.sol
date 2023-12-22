// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./IWrappedCharacters.sol";
import "./IItems.sol";
import "./IItemSets.sol";

contract StatManager is ReentrancyGuard {

    constructor (
          address itemsAddress,
          address mercenariesAddress,
          address itemSetsAddress
        )
        {
            require(itemsAddress != address(0), "Invalid Items Contract address");
            require(mercenariesAddress != address(0), "Invalid Mercenary Contract address");
            require(itemSetsAddress != address(0), "Invalid Item Sets Contract address");
            items = IItems(itemsAddress);
            mercenaries = IWrappedCharacters(mercenariesAddress);
            itemSets = IItemSets(itemSetsAddress);
        }

// STATE VARIABLES
   
    /// @dev This is the Wrapped Character contract
    IWrappedCharacters private mercenaries;

    /// @dev The Farmland Items contract
    IItems private items;

    /// @dev The Farmland Items Sets contract
    IItemSets private itemSets;

// MODIFIERS

    /// @dev Check if the explorer is inactive
    /// @param tokenID of explorer
    modifier onlyInactive(uint256 tokenID) {
        // Get the explorers activity
        (bool active,,,,,) = mercenaries.charactersActivity(tokenID);
        require (!active, "Explorer needs to complete quest");
        _;
    }

    /// @dev Must be the owner of the character
    /// @param tokenID of character
    modifier onlyOwnerOfToken(uint256 tokenID) {
        require (mercenaries.ownerOf(tokenID) == msg.sender,"Only the owner of the token can perform this action");
        _; // Call the actual code
    }  

    /// @dev Restore characters health with an item
    /// @param tokenID Characters ID
    /// @param itemID item ID
    /// @param total number of items to use
    function restoreHealth(uint256 tokenID, uint256 itemID, uint256 total)
        external
        nonReentrant
        onlyOwnerOfToken(tokenID)
        onlyInactive(tokenID)
    {
        require(items.balanceOf(msg.sender, itemID) >= total, "You don't have that item in your wallet");
        // Return the Item Modifiers values for Health items (21)
        (uint256 amountToIncrease, uint256 amountToBurn) = getItemModifier(21, itemID);
        //Check that the amount to increase is greater than zero, otherwise it's likely the item wasn't found in the set
        require(amountToIncrease > 0,"Item not found in this set");
        // Increase the health (5 = health item)
        mercenaries.increaseStat(tokenID, amountToIncrease*total, 5);  
        // Burn the health item(s)                     
        items.burn(msg.sender, itemID, amountToBurn * total);
    }

    /// @dev Restore characters morale with an item
    /// @param tokenID Characters ID
    /// @param itemID item ID
    /// @param total number of items to use
    function restoreMorale(uint256 tokenID, uint256 itemID, uint256 total)
        external
        nonReentrant
        onlyOwnerOfToken(tokenID)
        onlyInactive(tokenID)
    {
        require(items.balanceOf(msg.sender, itemID) >= total, "You don't have that item in your wallet");
        // Return the Item Modifiers values for Morale items (20)
        (uint256 amountToIncrease, uint256 amountToBurn) = getItemModifier(20, itemID);
        //Check that the amount to increase is greater than zero, otherwise it's likely the item wasn't found in the set
        require(amountToIncrease > 0,"Item not found in this set");
        // Increase the morale (6 = morale item)
        mercenaries.increaseStat(tokenID, amountToIncrease*total, 6);
        // Burn the morale item(s)
        items.burn(msg.sender, itemID, amountToBurn * total);
    }

    /// @dev Swap characters XP for a stat increase
    /// @param tokenID Characters ID
    /// @param amount which stat to increase
    /// @param statIndex amount to increase stat
    function boostStat(uint256 tokenID, uint256[] calldata amount, uint256[] calldata statIndex)
        external
        nonReentrant
        onlyOwnerOfToken(tokenID)
        onlyInactive(tokenID)
    {
        uint256 total = amount.length;
        //Check the array amount match
        require(total == statIndex.length, "The array totals must match");
        // Ensure maximum of 5 
        require(total < 6, "The array total exceeded");
        // Loop through the array
        for (uint256 i = 0; i < total;) {
            // Boost the characters stats
            mercenaries.boostStat(tokenID, amount[i] ,statIndex[i]);
            // Increment counter
            unchecked { ++i; }
        }
    }

// VIEWS

    /// @dev Return the Item Modifiers (value1 & value2)
    /// @param itemSet Item ID in use
    /// @param itemID item ID
    function getItemModifier(uint256 itemSet, uint256 itemID)
        private
        view
        returns (uint256 value1, uint256 value2)
    {
        require(itemSets.getItemSet(itemSet).length > 0,"No items found in this set");
        // Retrieve all the useful items for hazardous quests
        Item[] memory usefulItems = itemSets.getItemSet(itemSet);
        // Loop through the items
        for(uint256 i = 0; i < usefulItems.length;){
            // Check if the items are found and return the modifiers
            if (itemID == usefulItems[i].itemID) {
                value1 = usefulItems[i].value1;
                value2 = usefulItems[i].value2;
                break;
            }
            unchecked { ++i; }
        }
    }

}
