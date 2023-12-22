// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ItemTypes.sol";

abstract contract ItemCollection is ItemTypes {

// STATE VARIABLES

    /// @dev Contract name
    string public name;

    /// @dev Contract symbol
    string public symbol;

// EVENTS

    event ContractAddressChanged(address indexed account, string addressType, address newAddress);

// ADMIN FUNCTIONS

    /// @dev Update the description, name & symbol
    /// @param name_ Name of the contract
    /// @param symbol_ Contract symbol
    function updateCollectionDetails(
        string memory name_,
        string memory symbol_
        )
        external 
        onlyOwner 
    {
        name = name_;
        symbol = symbol_;
    }

// VIEWS

    /// @dev Return the token onchain metadata
    /// @param itemID Identifies the type of asset
    function uri(uint256 itemID) 
        public
        view
        override(ERC1155)
        returns (string memory output) 
    {
        require(itemID < totalItems+1, "Item not found");
        // Shortcut accessor
        ItemType memory item = items[itemID];
        // Store the rarity description rather than the id
        string memory rarity = "";
        if (item.rarity == 0) {
            rarity = "Common";
        } else if (item.rarity == 1) {
            rarity = "Uncommon";
        } else if (item.rarity == 2) {
            rarity = "Rare";
        } else if (item.rarity == 3) {
            rarity = "Epic";
        } else if (item.rarity == 4) {
            rarity = "Legendary";
        }
        // Encode the metadata
        string memory json = Base64.encode(abi.encodePacked(
            '{',
            '"name": "',            item.name, '",',
            '"description": "',     item.description, '",',
            '"animation_url": "',   item.animationUrl, '",',
            '"image": "',           item.imageUrl, '",',
            '"attributes": [',
                '{ "id": 0, "trait_type": "Rarity", "value": "' ,rarity, '" }',
                ']',
            '}'
        ));
        // Return the result
        return string(abi.encodePacked('data:application/json;base64,', json));
    }
}

