// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Permissioned.sol";
import "./IItems.sol";
import "./IItemSets.sol";

/// @dev Farmland - Item Sets Smart Contract
contract ItemSets is IItemSets, Permissioned {

// CONSTRUCTOR

    constructor (
        address itemsContractAddress
        ) Permissioned()
    {
        require(itemsContractAddress != address(0), "Invalid Items Contract address");
        // Define the ERC1155 Items Contract
        itemsContract = IItems(itemsContractAddress);
    }

// MODIFIERS

// STATE VARIABLES

    /// @dev The Farmland Items contract
    IItems internal immutable itemsContract;
        
    /// @dev Store the items in a set with a specific rarity [common, uncommon, rare, epic, legendary]
    /// @dev e.g., itemSetByRarity[itemSet][rarity]->[Item Struct]
    mapping (uint256 => mapping (uint256 => Item[])) private itemSetByRarity;

    /// @dev Store the items in a set
    /// @dev e.g., itemsBySet[itemSet]->[Item Struct Array]
    mapping (uint256 => Item[]) private itemsBySet;

    /// @dev Store a list of item sets
    uint256[] public sets;

// EVENTS

event ItemRegistered (address indexed account, uint256 itemID, uint256 itemRarity, uint256 itemSet);
event ItemDeregistered (address indexed account, uint256 itemID, uint256 itemSet);

// ADMIN FUNCTIONS
    
    /// @dev Register items in three separate mappings
    /// @param itemID ItemID
    /// @param itemSet Used to group items into a set
    /// @param itemValue1 Custom field ... can be used to register quest specific details (eg. item scacity cap, amount of land that can be found with certain items)
    /// @param itemValue2 Another custom field
    function registerItem(uint256 itemID, uint256 itemSet, uint256 itemValue1, uint256 itemValue2)
        external
        onlyOwner
    {
        // Retrieve the item details to store rarity in local variable
        ItemType memory item = itemsContract.getItem(itemID);
        // Write the items to mappings
        itemSetByRarity[itemSet][item.rarity].push(Item(itemID, itemSet, item.rarity, itemValue1, itemValue2));
        itemsBySet[itemSet].push(Item(itemID, itemSet, item.rarity, itemValue1, itemValue2));
        // Check if it's a new itemSet
        if (!setExists(itemSet)) {
            // add the itemSet to the sets array
            sets.push(itemSet);
        }
        // Write an event
        emit ItemRegistered (_msgSender(), itemID, item.rarity, itemSet);
    }

    /// @dev Deregister items from a set mapping
    /// @param itemSet Used to group items into a set
    /// @param itemRarity Defines the item rarity ... eg., common, uncommon, rare, epic, legendary
    /// @param index index of item in array
    function deregisterItemBySetAndRarity(uint256 itemSet, uint256 itemRarity, uint256 index)
        external
        onlyOwner
    {
        Item[] storage items = itemSetByRarity[itemSet][itemRarity];
        // Set the Item ID
        uint256 itemID = items[index].itemID;
        // In the items array swap the last item for the item being removed
        items[index] = items[items.length - 1];
        // Delete the final item in the items array
        items.pop();
        // Write an event
        emit ItemDeregistered(_msgSender(), itemID, itemSet);
    }

    /// @dev Deregister items from a set mapping
    /// @param itemSet Used to group items into a set
    /// @param index index of item in array
    function deregisterItemBySet(uint256 itemSet, uint256 index)
        external
        onlyOwner
    {
        Item[] storage items = itemsBySet[itemSet];
        // Set the Item ID
        uint256 itemID = items[index].itemID;
        // In the items array swap the last item for the item being removed
        items[index] = items[items.length - 1];
        // Delete the final item in the items array
        items.pop();
        // Write an event
        emit ItemDeregistered(_msgSender(), itemID, itemSet);
    }

// VIEWS

    /// @dev Check if an itemSet exists
    /// @param itemSet Item Set e.g., a grouping of items for selection
    function setExists(uint256 itemSet)
        public
        view
        returns (bool exists)
    {
        uint256 total = sets.length;
        for(uint256 i = 0; i < total;){
            if (sets[i] == itemSet) {
                return true;
            }
            unchecked { ++i; }
        }
    }

    /// @dev Retrieve list of itemSets
    function getSets()
        external
        view
        returns (uint256[] memory itemSets)
    {
        return sets;
    }

    /// @dev Retrieve list of Items by set
    /// @param itemSet Item Set e.g., a grouping of items for selection
    function getItemSet(uint256 itemSet)
        external
        view
        returns (Item[] memory items) // Define the array of items to be returned.
    {
        // Return list of items
        return itemsBySet[itemSet];
    }

    /// @dev Retrieve list of Items based on rarity
    /// @param itemRarity Item Rarity e.g., common = 0, uncommon=1 etc.
    /// @param itemSet Item Set e.g., Raw Material etc.
    function getItemSetByRarity(uint256 itemSet, uint256 itemRarity)
        external
        view
        returns (Item[] memory items) // Define the array of items to be returned.
    {
        // Return list of items
        return itemSetByRarity[itemSet][itemRarity];
    }

}
