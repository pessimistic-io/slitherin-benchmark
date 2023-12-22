//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Pausable.sol";

import "./UserAccessible.sol";
import "./LocationManager.sol";
import "./VaultManager.sol";
import "./KitchenManager.sol";
import "./Probable.sol";
import "./EOA.sol";

import "./UserAccessible_Constants.sol";

/**
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMKkkkkkKMMMMMMMMMMMMWKkKWMMMMMMMMMMMMMWKkKMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMWk;.   ;xkkkkkkkkkkkx; ;xkkkkkkkkKWMMMWl.;xkkkkkkkkKWMWKkxkkkkkkKWMMMMMMMMMWKkkkkkkkkkkkKMMMKkkkkkkkkkkkkkkkkkkkKWKkkkkkKWMMMM
MMMMNl     .;;;;;;;;;;;.           lWMMMWl           lWMWk:;;.    ;xkkkkKWMMMWl   .;;;;;. lWMWk;.     .;;;;;;;.   lNo   .:kWMMMM
MMMMWl     lNWWWWWWWWWNc .,,,,,,,,;kWMMMWl .,,,,,,,,;kWMMMWWNl      .;;:kWMMMWl   lNWWWNc lWMMWNl     lNWWWWWNl   ,d,   lNWMMMMM
MMMMWl     ,xkkkkKWMMMWl lNWW0xxxxxxkkkkx, lNWW0xxxxxKMMMMMMWl      lNWWWMMMMWl   ,xkkkx, lWMMMWl     lWMMMMMWk;.   .,,;kWMMMMMM
MMMMWl           lWMMMWl lWMWl     .;;;;;. lWMWl     lWMMMMMWl      lWMMMMMMMWl         .;kWMMMWl     lWMMMMMMWNl   lNWWMMMMMMMM
MMMMWl     .,,,,;kWMMMWl lWMWl     lNWWWNc lWMWl     lWMMMMMWl      lWMMMMMMMWl   .,,,. lNWMMMMWl     lWMMMMMMKx,   ,xkkKMMMMMMM
MMMMWl     lNWWWWMMMMMWl lWMWl     lWMMMWl lWMWl     lWMMMMMWl      lWMMMMMMMWl   lNWNc lWMMMMMWl     lWMMMMMWl   .,.   lWMMMMMM
MMMMWl     ,xkkkkkkKMMWl ,xkx,     lWMMMWl ,xkx,     ,xkkkkkx,      ,xkkkkkkkx,   lWMWl ,xkkkkkx,     ,xKWMWKx,   lXl   ,xKWMMMM
MMMMWk;,,,,;;;;;;;:kWMWk;;;;;;,,,,;kWMMMWk;;;;;;,,,,,;;;;;;;;;,,,,,,;;;;;;;;;;;,,;kWMWk;;;;;;;;;;,,,,,;:kWMWk:;,,;kNk;,,;:kWMMMM
MMMMMWWWWWWWWWWWWWWMMMMMWWWWWWWWWWWWMMMMMWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWMMMMMWWWWWWWWWWWWWWWWWMMMMMWWWWWMMMWWWWWMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
*/

contract EGGTRIXV1 is 
  LocationManager,
  KitchenManager,
  VaultManager,
  Probable,
  UserAccessible,
  EOA,
  Pausable
{
  
  constructor(
    address kitchen,
    address location,
    address tokenVault,
    address userAccess
  ) 
    KitchenManager(kitchen)
    LocationManager(location)
    VaultManager(tokenVault)
    UserAccessible(userAccess)
  {}

  function setContracts (
    address kitchen,
    address location,
    address tokenVault
  )
    public
    adminOrRole(EGGTRIX_ROLE)
    onlyEOA
  {
    _setTokenLocation(location);
    _setKitchen(kitchen);
    _setTokenVault(tokenVault);
  }

  function pause () public adminOrRole(EGGTRIX_ROLE) onlyEOA { _pause(); }
  function unpause () public adminOrRole(EGGTRIX_ROLE) onlyEOA { _unpause(); }

  function withdrawTokens (
    uint[] calldata playerIds
  ) 
    public 
    whenNotPaused
    onlyEOA
  {
    for (uint i = 0; i < playerIds.length; i++) {
      uint playerId = playerIds[i];
      require(location.atLocation(playerId, LOCATION_CHILL), 'BUSY');
      tokenVault.withdrawToken(playerId, msg.sender);
      location.setLocation(playerId, LOCATION_NONE);
    }
  }

  function depositTokens (
    UserToken[] calldata tokens
  ) 
    public 
    whenNotPaused
    onlyEOA
  {
    UserToken memory token;
    uint playerId;
    for (uint i = 0; i < tokens.length; i++) {
      token = tokens[i];
      playerId = tokenVault.resolvePlayerId(token);
      tokenVault.depositToken(token, msg.sender);
      location.setLocation(playerId, LOCATION_CHILL);
    }
  }

  function cook (
    uint[] calldata playerIds, 
    uint[] calldata itemIds
  ) 
    public 
    whenNotPaused
    onlyEOA
  {
    require(playerIds.length == itemIds.length, 'NON_EQUAL_LENGTH');
    for (uint i = 0; i < playerIds.length; i++) {
      uint playerId = playerIds[i];
      requireOwnershipOf(playerId, msg.sender);
      requirePlayableToken(playerId);
      require(location.atLocation(playerId, LOCATION_CHILL), 'BUSY');
      kitchen.cookFor(msg.sender, playerId, itemIds[i]);
      location.setLocation(playerId, LOCATION_KITCHEN);
    }
  }

  function claimFood (
    uint[] calldata playerIds
  ) 
    public 
    whenNotPaused
    onlyEOA
  {
    for (uint i = 0; i < playerIds.length; i++) {
      uint playerId = playerIds[i];
      requireOwnershipOf(playerId, msg.sender);
      requirePlayableToken(playerId);
      require(location.atLocation(playerId, LOCATION_KITCHEN), 'NOT_COOKING');
      kitchen.claimFor(msg.sender, playerId, baseChance);
      location.setLocation(playerId, LOCATION_CHILL);
    }
  }

  function claimFoodAndCook (
    uint[] calldata playerIds,
    uint[] calldata itemIds
  ) 
    public 
    whenNotPaused
    onlyEOA
  {
    require(playerIds.length == itemIds.length, 'NON_EQUAL_LENGTH');
    for (uint i = 0; i < playerIds.length; i++) {
      uint playerId = playerIds[i];
      requireOwnershipOf(playerId, msg.sender);
      requirePlayableToken(playerId);
      require(location.atLocation(playerId, LOCATION_KITCHEN), 'NOT_COOKING');
      kitchen.claimFor(msg.sender, playerId, baseChance);
      kitchen.cookFor(msg.sender, playerId, itemIds[i]);
    }
  }
  
}
