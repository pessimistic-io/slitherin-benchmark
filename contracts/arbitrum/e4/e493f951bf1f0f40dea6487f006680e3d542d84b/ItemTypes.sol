// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC1155Supply.sol";
import "./ERC1155Burnable.sol";
import "./ReentrancyGuard.sol";
import "./Base64.sol";
import "./IItems.sol";
import "./Permissioned.sol";

abstract contract ItemTypes is ERC1155Supply, ERC1155Burnable, IItems, ReentrancyGuard, Permissioned {

// CONSTRUCTOR

    constructor () Permissioned() { }

// STATE VARIABLES

    /// @dev Mapping for the items
    mapping(uint256 => ItemType) public items;
    
    /// @dev Keeps track of total number of items
    uint256 public totalItems;

// MODIFIERS       

    /// @dev Checks whether a minting has started
    /// @param itemID identifies the type of asset
    modifier onlyWhenMintingActive(uint256 itemID) {
        require(items[itemID].mintingActive, "Minting not started");
        _;
    }

    /// @dev Checks whether an item exists
    /// @param itemID identifies the type of asset
    modifier onlyIfItemExists(uint256 itemID) {
        require(itemID <= totalItems,"Item does not exist");
        _;
    }

// EVENTS

    event ItemSetInUse(address indexed account, uint256 indexed tokenID, uint256 indexed itemID, uint256 amount, bool inUse);
    event SetItemID(address indexed account, uint256 oldItemID, uint256 newItemID);

    /// @dev The owner can add a new item to the contract
    /// @param item item type struct
    function addItem(ItemType calldata item)
        external
        onlyOwner
    {
        // Increment the total items
        unchecked { ++totalItems; }
        // Set the item details
        items[totalItems] = item;
    }

    /// @dev The owner can update an item
    /// @param itemID ID of the item
    /// @param item item type struct
    function updateItem(uint256 itemID, ItemType calldata item)
        external 
        onlyOwner
        onlyIfItemExists(itemID)
    {
        // Set the item details
        items[itemID] = item;
    }

    /// @dev The owner can delete an item
    /// @param itemID ID of the item
    function deleteItem(uint256 itemID)
        external 
        onlyOwner
        onlyIfItemExists(itemID)
    {
        // delete the item mapping
        delete items[itemID];
    }

    /// @dev The owner can set the next item ID
    /// @dev To be used in conjunction with deleteItem
    /// @param nextItemID ID of the item
    function setNextItemID(uint256 nextItemID)
        external 
        onlyOwner
    {
        emit SetItemID(_msgSender(), totalItems, nextItemID);
        totalItems = nextItemID;
    }

    /// @dev Allows the owner to start & stop all minting
    function startOrStopMinting(bool value) 
        external
        onlyOwner
    {
        // Store totalItems into a local variable to save gas
        uint256 total = totalItems;
        // Loop through all items
        for (uint256 i = 1; i <= total;) {
            // Set the mint active flag
            items[i].mintingActive = value;
            unchecked { ++i; }
        }
    }

    /// @dev Set an amount of an item as in use
    /// @param account account to use
    /// @param tokenID Id of NFT
    /// @param itemID Id of item 
    /// @param amount to set as in use
    /// @param inUse true or false
    function setItemInUse(address account, uint256 tokenID, uint256 itemID, uint256 amount, bool inUse)
        public
        override
        onlyAllowed
    {
        if (inUse) {
            require(amount <= balanceOf(account,itemID),"Not enough items");
            // Store the amount in use by Account
            getItemsInUse[account][itemID] += amount;
            // Store the amount in use by TokenID
            getItemsInUseByToken[tokenID][itemID] += amount;
        } else {
            // Remove the amount in use by Account
            delete getItemsInUse[account][itemID];
            // Remove the amount in use by TokenID
            delete getItemsInUseByToken[tokenID][itemID];
        }
        // Write an event
        emit ItemSetInUse(account, tokenID, itemID, amount, inUse);
    }

    /// @dev Set a series of items as in use
    /// @param accounts accounts to use
    /// @param tokenIDs Ids of NFT
    /// @param itemIDs Ids of items
    /// @param amounts to set as in use
    /// @param inUse true or false
    function setItemsInUse(address[] calldata accounts, uint256[] calldata tokenIDs, uint256[] calldata itemIDs, uint256[] calldata amounts, bool[] calldata inUse)
        external
        override
        onlyAllowed
    {
        require(accounts.length == tokenIDs.length && 
                tokenIDs.length == itemIDs.length && 
                itemIDs.length == amounts.length && 
                amounts.length == inUse.length, "Array lengths don't match");
        uint256 total = accounts.length;
        for(uint256 i = 0; i < total;){
            // Call function to set item in use
            setItemInUse(accounts[i], tokenIDs[i], itemIDs[i], amounts[i], inUse[i]);
            unchecked { ++i; }
        }
    }

// GETTERS

    /// @dev Returns an item
    /// @param itemID ID of the item
    function getItem(uint256 itemID)
        external
        override
        view
        returns (ItemType memory item)
    {
        return items[itemID];
    }

    /// @dev Returns a list of all items
    function getItems()
        external
        override
        view
        returns (ItemType[] memory allItems) 
    {
        // Store total number of items into a local variable
        uint256 total = totalItems;
        if ( total == 0 ) {
            // if no items added, return an empty array
            return new ItemType[](0);
        } else {
            allItems = new ItemType[](total+1);
            // Push a blank item into the array as there isn't an item with Id zero
            allItems[0] = ItemType (0,0,'','','','',false,false,0,0,0,0);
            // Loop through the items
            for(uint256 i = 1; i < total+1;){
                // Add item to array
                allItems[i] = items[i];
                unchecked { ++i; }
            }
        }
    }

    /// @dev Returns a list of all active items by tokenID
    /// @param tokenID Id of NFT
    function getActiveItemsByTokenID(uint256 tokenID)
        external
        override
        view
        returns (uint256[] memory itemsByToken)
    {
        // Store total number of items into a local variable
        uint256 total = totalItems;
        uint256 totalByToken = 0;
        if ( total == 0 ) {
            // if no items added, return an empty array
            return new uint256[](0);
        } else {
            // Loop through the items to determine the count
            for(uint256 i = 1; i < total+1;) {               
                // Check if item is in use                
                if (getItemsInUseByToken[tokenID][i] > 0) {
                    // Increment total
                    unchecked { ++totalByToken; }
                }
                unchecked { ++i; } 
            }
            itemsByToken = new uint256[](totalByToken);
            uint256 index = 0;
            // Loop through the items
            for(uint256 i = 1; i < total+1;) {
                // Check if item is in use
                if (getItemsInUseByToken[tokenID][i] > 0) {
                    // Add itemID to array
                    itemsByToken[index] = i;
                    unchecked { ++index; }
                }
                unchecked { ++i; }
            }
        }
    }

    ///@dev Override balanceOf to exclude itemsInUse, balanceOfBatch uses balanceOf
    function balanceOf(address account, uint256 id) public view virtual override (IERC1155, ERC1155) returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");
        uint256 amountOfItemsInUse = getItemsInUse[account][id];
        if (amountOfItemsInUse > 0) {
            return super.balanceOf(account,id) - amountOfItemsInUse;
        } else {
            return super.balanceOf(account,id);
        }
    }

    function burn(address account,uint256 id,uint256 value) public override (IERC1155Burnable, ERC1155Burnable) {
        ERC1155Burnable.burn(account, id, value);
    }

    function burnBatch(address account,uint256[] memory ids,uint256[] memory values) public override (IERC1155Burnable, ERC1155Burnable) {
        ERC1155Burnable.burnBatch(account, ids, values);
    }

    function totalSupply(uint256 id) public view override (IERC1155Supply, ERC1155Supply) returns (uint256) {
        return ERC1155Supply.totalSupply(id);
    }

    function exists(uint256 id) public view override (IERC1155Supply, ERC1155Supply) returns (bool) {
        return ERC1155Supply.exists(id);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override (ERC1155, IERC165, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @dev The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override(ERC1155, ERC1155Supply)
    {
        // Adjusts standard ERC1155 transfer functionality to revert if any of the items are non transferrable
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data); // transfers enabled as normal

        uint256 total = ids.length;
        for(uint256 i = 0; i < total;){
            // Check balance - items in use is greater than the amount to be transferred 
            uint256 amountOfItemsInUse = getItemsInUse[from][ids[i]];
            if (amountOfItemsInUse > 0) {
                require(balanceOf(from,ids[i]) >= amounts[i],"Items in use, balance too low");
            }
            // Check if soulbound & ensure not minting or burning
            if (items[ids[i]].soulbound){
                require(from == address(0) || to == address(0), "Token is nontransferable");
            }
            unchecked { ++i; }
        }
    }

}
