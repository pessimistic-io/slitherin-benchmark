// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITokenVault.sol";

abstract contract VaultManager {

  ITokenVault public tokenVault;

  constructor (address _tokenVault) {
    _setTokenVault(_tokenVault);
  }

  function requireDepositableToken (UserToken memory token) internal view {
    require(tokenVault.depositableToken(token), 'UNAUTH_DEPOSIT');
  }

  function requirePlayableToken (uint playerId) internal view {
    require(tokenVault.playableToken(playerId), 'TOKEN_UNPLAYABLE');
  }

  function requireOwnershipOf (uint playerId, address owner) internal view {
    require(_ownsToken(playerId, owner),'NOT_OWNER');
  }

  function _ownsToken (uint playerId, address owner) view internal returns (bool) {
    return tokenVault.ownerOf(playerId) == owner;
  }

  function _setTokenVault (address _tokenVault) internal {
    tokenVault = ITokenVault(_tokenVault);
  }

}
