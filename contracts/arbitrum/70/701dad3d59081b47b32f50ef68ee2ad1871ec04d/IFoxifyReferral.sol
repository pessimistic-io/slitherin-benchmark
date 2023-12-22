// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFoxifyReferral {
    function maxTeamID() external view returns (uint256);

    function teamOwner(uint256) external view returns (address);

    function userTeamID(address) external view returns (uint256);

    event TeamCreated(uint256 teamID, address owner);
    event TeamJoined(uint256 indexed teamID, address indexed user);
}

