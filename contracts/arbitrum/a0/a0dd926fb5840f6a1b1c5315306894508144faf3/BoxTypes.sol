// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pausable.sol";
import "./Permissioned.sol";

struct Box { 
    /// @dev The name of the box
    string name;
    /// @dev This is the amount of ETH required for the box
    uint256 boxPrice;
    /// @dev This is the number of Citizen in the box
    uint256 numberOfCitizens;
    /// @dev This is the amount of ETH required for the Citizen
    uint256 citizenPrice;
    /// @dev This is the box ID to include in the box
    uint256 packID;
    /// @dev This is the total number of boxes to include in the box
    uint256 numberOfPacks;
    /// @dev This is the total number of items in a box to include in the box (3 = small, 5= medium, 10 = large)
    uint256 numberOfItemsInPack;
    /// @dev This is the total number of mercenaries to include in the box
    uint256 numberOfMercenaries;
    /// @dev This is the amount of Land to include in the box
    uint256 amountOfLand;
    /// @dev Status (Active/Inactive)
    bool active;                     
    }

/// @dev Farmland - Box Type Smart Contract
contract BoxTypes is Pausable, Permissioned {

    constructor () Permissioned() {}

// STATE VARIABLES

    /// @dev Create a mapping to track each type of box
    mapping(uint256 => Box) public boxes;

    /// @dev Tracks the last Box ID
    uint256 public lastBoxID;

// MODIFIERS

    /// @dev Check if items registered
    modifier onlyWhenBoxEnabled(uint256 boxID) {
        require (boxes[boxID].active, "Boxes: Box inactive");
        _;
    }
    
    /// @dev Checks whether an box exists
    /// @param boxID identifies the box
    modifier onlyIfBoxExists(uint256 boxID) {
        require(boxID < lastBoxID,"Boxed: Box does not exist");
        _;
    }

// ADMIN FUNCTIONS


    /// @dev Adds a new box to the game
    /// @param box Box struct
    function addBox(Box calldata box)
        external
        onlyOwner
    {
        // Set the box details
       boxes[lastBoxID] = box;
        // Increment the total items
        unchecked { ++lastBoxID; }
    }

    /// @dev The owner can update an box
    /// @param boxID ID of the box
    /// @param box box  struct
    function updateBox(uint256 boxID, Box calldata box)
        external 
        onlyOwner
        onlyIfBoxExists(boxID)
    {
        // Set the box details
       boxes[boxID] = box;
    }

    /// @dev The owner can delete an box
    /// @param boxID ID of the box
    function deleteBox(uint256 boxID)
        external 
        onlyOwner
        onlyIfBoxExists(boxID)
    {
        delete boxes[boxID];
    }

    /// @dev Start or pause the contract
    /// @param value to start or stop the contract
    function isPaused(bool value)
        external
        onlyOwner
    {
        if ( !value ) {
            _unpause();
        } else {
            _pause();
        }
    }

// INTERNAL FUNCTIONS

    /// @dev Returns an array of all boxes
    function getBoxes()
        external
        view
        returns (Box[] memory allBoxes)
    {
        // Store total number of boxes into a local variable
        uint256 total = lastBoxID;
        if ( total == 0 ) {
            // if no boxes added, return an empty array
            return allBoxes;
        } else {
            // Loop through the boxes
            allBoxes = new Box[](total);
            for(uint256 i = 0; i < total;) {
                // Add boxes to array
                allBoxes[i] = boxes[i];
                unchecked { ++i; }
            }
        }
    }

}
