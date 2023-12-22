// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ItemCollection.sol";

/// @dev Farmland - Items Smart Contract
contract Items is ItemCollection {

// CONSTRUCTOR

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC1155("on-chain-metadata") {
        name = name_;
        symbol = symbol_;
    }

// USER FUNCTIONS

    /// @dev Mint item tokens
    /// @param itemID identifies the type of asset
    /// @param amount how many tokens to be minted
    /// @param recipient who will receive the minted tokens
    function mintItem(uint256 itemID, uint256 amount, address recipient)
        external
        override
        nonReentrant
        onlyAllowed
        onlyIfItemExists(itemID)
        onlyWhenMintingActive(itemID)
    {
        // If a max supply is defined ensure it isn't exceeded
        if (items[itemID].maxSupply != 0) {
            require(totalSupply(itemID) + amount <= items[itemID].maxSupply, "Max supply exceeded");
        }
        // Mint item
        _mint(recipient, itemID, amount, "");
    }

    /// @dev Mint a set of item tokens
    /// @param itemIDs identifies the tokens to be minted (array)
    /// @param amounts how many tokens to be minted (array)
    /// @param recipient who will receive the minted tokens
    function mintItems(uint256[] calldata itemIDs, uint256[] calldata amounts, address recipient)
        external
        override
        nonReentrant
        onlyAllowed
    {
        // Store the total items IDs passed
        uint256 total = itemIDs.length;
        require (total == amounts.length,"Items arrays length's don't match");
        uint256 itemID;
        // Loop through the contracts
        for(uint256 i = 0; i < total;){
            // Store the itemID in local variable
            itemID = itemIDs[i];
            require(items[itemID].mintingActive, "Minting not started");
            require(itemID < totalItems, "Item does not exist");
            // If a max supply is defined ensure it isn't exceeded
            if (items[itemID].maxSupply != 0) {
                require(totalSupply(itemID) + amounts[i] <= items[itemID].maxSupply, "Max supply exceeded");
            }
            unchecked { ++i; }
        }
        // Mint items
        _mintBatch(recipient, itemIDs, amounts, "");
    }

}
