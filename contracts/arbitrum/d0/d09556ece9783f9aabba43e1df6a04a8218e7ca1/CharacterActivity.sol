// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CharacterStats.sol";

contract CharacterActivity is CharacterStats {

// STATE VARIABLES

    /// @dev A mapping to track a characters activity
    mapping(uint256 => Activity) public charactersActivity;

// EVENTS

    event ActivityStatusUpdated(address indexed account, uint256 indexed tokenID, bool active);
    event ActivityStarted(address indexed account, uint256 indexed tokenID, Activity activity); 

// EXTERNAL FUNCTIONS

    /// @dev Update characters activity status
    /// @param tokenID Characters ID
    /// @param active the amount
    function _updateActivityStatus(uint256 tokenID, bool active)
        internal
    {
        // Write an event to the chain
        emit ActivityStatusUpdated(_msgSender(), tokenID, active);
        // Set active
        charactersActivity[tokenID].active = active;
        if (!active) {
            // Set block at which the activity completes
            charactersActivity[tokenID].completedBlock = block.number;
        }
    }

    /// @dev Update characters Activity Details
    /// @param tokenID Characters ID
    /// @param activity the activity details defined in the Activity struct
    function _startActivity(uint256 tokenID, Activity calldata activity)
        internal
    {
        require(activity.endBlock > activity.startBlock, "End block should be higher than start");
        // Write an event to the chain
        emit ActivityStarted(_msgSender(), tokenID, activity);
        // Set the activity details
        charactersActivity[tokenID] = activity;
    }

//VIEWS

    /// @dev PUBLIC: Blocks remaining in activity, returns 0 if finished
    /// @param tokenID Characters ID
    function getBlocksUntilActivityEnds(uint256 tokenID)
        external
        view
        returns (
                uint256 blocksRemaining
        )
    {
        // Shortcut to characters activity
        Activity storage activity = charactersActivity[tokenID];
        if (activity.endBlock > block.number) {
            return activity.endBlock - block.number;
        }
    }

}
