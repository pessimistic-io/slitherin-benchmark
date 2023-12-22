// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces_IERC1155.sol";
import "./IERC1155Burnable.sol";
import "./IERC1155Supply.sol";

/// @dev Defines the ItemType struct
struct ItemType {
    uint256 itemID;
    uint256 maxSupply;
    string name;
    string description;
    string imageUrl;
    string animationUrl;
    bool mintingActive;
    bool soulbound;
    uint256 rarity;
    uint256 itemType;
    uint256 wearableType;
    uint256 value1;
}

abstract contract IItems is IERC1155, IERC1155Burnable, IERC1155Supply {
    /// @dev A mapping to track items in use by account
    /// @dev getItemsInUse[account].[itemID] = amountOfItemsInUse
    mapping (address => mapping(uint256 => uint256)) public getItemsInUse;

    /// @dev A mapping to track items in use by tokenID
    /// @dev getItemsInUseByToken[tokenID].[itemID] = amountOfItemsInUse
    mapping (uint256 => mapping(uint256 => uint256)) public getItemsInUseByToken;

    function mintItem(uint256 itemID, uint256 amount, address recipient) external virtual;
    function mintItems(uint256[] memory itemIDs, uint256[] memory amounts, address recipient) external virtual;
    function setItemInUse(address account, uint256 tokenID, uint256 itemID, uint256 amount, bool inUse) external virtual;
    function setItemsInUse(address[] calldata accounts, uint256[] calldata tokenIDs, uint256[] calldata itemIDs, uint256[] calldata amounts, bool[] calldata inUse) external virtual;
    function getItem(uint256 itemID) external view virtual returns (ItemType memory item);
    function getItems() external view virtual returns (ItemType[] memory allItems);
    function getActiveItemsByTokenID(uint256 tokenID) external view virtual returns (uint256[] memory itemsByToken);
}
