// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IWrappedCharacters.sol";
import "./Permissioned.sol";

contract CollectionManager is Permissioned {

// CONSTRUCTOR

    constructor () Permissioned() {}

// STATE VARIABLES

    /// @dev Create an array to track the Character collections
    mapping(address => Collection) public characterCollections;

// MODIFIERS

    /// @dev Check if the collection is wrappable
    /// @param collectionAddress address of collection
    modifier isRegistered(address collectionAddress) {
        require(isCollectionEnabled(collectionAddress) || collectionAddress == address(this),"This collection is not registered");
        _;
    }

    /// @dev Check if the collection is wrappable
    /// @param collectionAddress address of collection
    modifier isWrappable(address collectionAddress) {
        require(isCollectionEnabled(collectionAddress) && collectionAddress != address(this),"This collection is not wrappable");
        _;
    }

// EVENTS
    event CollectionEnabled(address indexed account, address collectionAddress, bool native, uint256 range, uint256 offset);
    event CollectionDisabled(address indexed account, address collectionAddress);

// FUNCTIONS

    /// @dev Enables a NFT collection to be wrapped
    /// @param collectionAddress address of the NFT collection
    /// @param native is this a native Farmland NFT collection
    /// @param range the max range for non native stats i.e, when added to the offset the range gives the maximum stat
    /// @param offset the offset for not native stats i.e., the floor for stats
    function enableCollection(address collectionAddress, bool native, uint256 range, uint256 offset)
        external
        onlyOwner
    {
        // Flag if collection is native to farmland
        characterCollections[collectionAddress].native = native;
        // Add range to the collection mapping
        characterCollections[collectionAddress].range = range;
        // Add offset to the collection mapping
        characterCollections[collectionAddress].offset = offset;
        emit CollectionEnabled(_msgSender(), collectionAddress, native, range, offset);
    }

    /// @dev Disables a NFT collection from being wrapped
    /// @param collectionAddress address of the NFT collection
    function disableCollection(address collectionAddress)
        external
        onlyOwner
    {
        // Delete the mapping
        delete characterCollections[collectionAddress];
        emit CollectionDisabled(_msgSender(), collectionAddress);
    }

// VIEWS

    /// @dev Is a NFT collection enabled for wrapping
    /// @param collectionAddress address of the NFT collection
    function isCollectionEnabled(address collectionAddress)
        public
        view
        returns (
            bool enabled
        )
    {
        if (characterCollections[collectionAddress].range > 0) {
            return true;
        }
    }

}
