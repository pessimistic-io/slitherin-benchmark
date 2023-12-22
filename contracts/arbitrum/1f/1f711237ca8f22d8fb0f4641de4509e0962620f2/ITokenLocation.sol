//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TokenVault_Types.sol";
import "./UserAccessible_Constants.sol";

interface ITokenLocation {
  function playerAtLocationByIndex (uint locationId, uint index) external view returns (uint);
  function playersAtLocation (uint locationId) external view returns (uint);
  function setLocation (uint playerId, uint locationId) external;
  function atLocation (uint playerId, uint locationId) external view returns (bool);
  function locationOf (uint playerId) external view returns (uint);
  function locationSince (uint playerId) external view returns (uint);
}
