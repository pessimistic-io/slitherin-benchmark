// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

abstract contract AddressWhitelist is Ownable {

// STATE VARIABLES

    /// @dev Array stores a mapping for all the whitelisted contracts
    address[] public whitelist;

// MODIFIERS

    /// @dev Checks whether an contract is whitelisted
    modifier onlyWhitelisted() {
        (bool whitelisted, uint256 index) = checkWhitelist(_msgSender());
        require(whitelisted, "Only whitelisted contracts");
       _;
    }

// EVENTS

    event AddressWhitelisted(address updatedBy, address whitelistAddress);

// ADMIN FUNCTIONS

    /// @dev Flips the whitelist address for an item on or off
    /// @param whitelistAddress address to check for whitelist
    function addWhitelist(address whitelistAddress)
        external
        onlyOwner
    {
        whitelist.push(whitelistAddress);                  // Create newItemWhitelist
        emit AddressWhitelisted(_msgSender(), whitelistAddress);         // Write an event to the chain
    }

    /// @dev Removes the address from an items whitelist
    /// @param whitelistAddress address to remove from whitelist
    function removeWhitelist(address whitelistAddress)
        external
        onlyOwner
    {
        (bool whitelisted, uint256 index) = checkWhitelist(whitelistAddress);
        require(whitelisted,                                 "Address not found on whitelist");
        whitelist[index] = whitelist[whitelist.length - 1];  // Overwrite the item to delete with the last item in the array
        whitelist.pop();                                     // Delete the last item in the array
    }

// VIEW FUNCTIONS

    /// @dev Check a whitelist address for an item
    /// @param whitelistAddress address to check for whitelist
    function checkWhitelist(address whitelistAddress)
        public
        view
        returns (
            bool whitelisted,
            uint256 addressIndex)
    {
        uint256 total = whitelist.length;                  // Get the current whitelist array index
        for(uint256 i=0; i < total; i++){                  // Loop through the addresses
            if ( whitelistAddress == whitelist[i]) 
            {
                addressIndex = i;                          // If we get a match on address in whitelist return the index ID
                whitelisted = true;                        // If we get a match on address in whitelist return true
            }
        }
    }

}
