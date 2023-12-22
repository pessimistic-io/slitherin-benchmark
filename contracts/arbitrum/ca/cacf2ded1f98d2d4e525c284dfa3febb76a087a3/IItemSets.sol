// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @param itemID ItemID
/// @param itemSet Used to group items into a set
/// @param rarity Defines the item rarity ... eg., common, uncommon, rare, epic, legendary
/// @param itemValue1 Custom field ... can be used to define quest specific details (eg. item scacity cap, amount of land that can be found with certain items)
/// @param itemValue2 Another custom field ... can be used to define quest specific details (e.g., the amount of an item to burn, potions)
struct Item {uint256 itemID; uint256 itemSet; uint256 rarity; uint256 value1; uint256 value2;}

/// @dev Farmland - Items Sets Interface
interface IItemSets {
    function getItemSet(uint256 itemSet) external view returns (Item[] memory itemsBySet);
    function getItemSetByRarity(uint256 itemSet, uint256 itemRarity) external view returns (Item[] memory itemsBySetAndRarity);
}
