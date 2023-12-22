// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IFoxifyReferral.sol";

contract FoxifyReferral is IFoxifyReferral {
    uint256 public maxTeamID;
    mapping(uint256 => address) public teamOwner;
    mapping(address => uint256) public userTeamID;

    /**
     * @notice Create a new team.
     * @return teamID Newly created team id.
     */
    function createTeam() external returns (uint256 teamID) {
        maxTeamID += 1;
        teamID = maxTeamID;
        teamOwner[teamID] = msg.sender;
        emit TeamCreated(teamID, msg.sender);
    }

    /**
     * @notice Create a new team.
     * @param teamID The id of team for join.
     * @return True if the operation was successful, false otherwise.
     */
    function joinTeam(uint256 teamID) external returns (bool) {
        require(teamID > 0 && teamID <= maxTeamID, "FoxifyReferral: Invalid team id");
        userTeamID[msg.sender] = teamID;
        emit TeamJoined(teamID, msg.sender);
        return true;
    }
}

