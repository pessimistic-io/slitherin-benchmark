//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EnumerableSet.sol";

import "./UserAccessible_Constants.sol";
import "./Types.sol";
import "./UserAccessible.sol";

contract TokenLocation is 
  UserAccessible
{
  using EnumerableSet for EnumerableSet.UintSet;

  mapping (uint => Location) playerToLocation; // playerId => locationId
  mapping (uint => EnumerableSet.UintSet) locationToPlayers; // locationId => playerIds

  constructor (address _userAccess)
    UserAccessible(_userAccess)
  {}

  function locationOfPlayers (uint[] memory playerIds) public view returns (uint[] memory) {
    uint[] memory locations = new uint[](playerIds.length);
    for(uint i = 0; i < playerIds.length; i++) {
      locations[i] = locationOf(playerIds[i]);
    }
    return locations;
  }

  function playerAtLocationByIndex (uint locationId, uint index) public view returns (uint) {
    return locationToPlayers[locationId].at(index);
  }

  function playersAtLocation (uint locationId) public view returns (uint) {
    return locationToPlayers[locationId].length();
  }

  function locationOf (uint playerId)
    public
    view
    returns (uint)
  {
    return playerToLocation[playerId].id;
  }

  function locationSince (uint playerId)
    public
    view
    returns (uint)
  {
    return playerToLocation[playerId].timestamp;
  }

  function setLocation (uint playerId, uint locationId) 
    public 
    adminOrRole(LOCATION_ROLE)
  {
    _setLocation(playerId, locationId);
  }

  function atLocation (uint playerId, uint locationId) public view returns (bool) {
    return playerToLocation[playerId].id == locationId;
  }

  function _setLocation (uint playerId, uint locationId) private {
    uint currentLocation = playerToLocation[playerId].id;
    locationToPlayers[currentLocation].remove(playerId);
    playerToLocation[playerId] = Location({
      id: locationId,
      timestamp: block.timestamp
    });
    locationToPlayers[locationId].add(playerId);
  }
}
