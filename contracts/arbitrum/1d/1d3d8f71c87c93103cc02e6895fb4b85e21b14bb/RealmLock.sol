// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";

import "./IRealm.sol";

import "./ManagerModifier.sol";

contract RealmLock is ReentrancyGuard, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;

  //=======================================
  // Int
  //=======================================
  uint256 public maxLock;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) public locked;

  //=======================================
  // Modifiers
  //=======================================
  modifier isRealmOwner(uint256 _realmId) {
    _isRealmOwner(_realmId);
    _;
  }

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    uint256 _maxLock
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);

    maxLock = _maxLock;
  }

  //=======================================
  // External
  //=======================================
  function lock(uint256 _realmId, uint256 _hours)
    external
    nonReentrant
    isRealmOwner(_realmId)
  {
    // Hours must be greater than zero
    require(_hours > 0, "RealmLock: Hours must be greater than zero");

    // Check if hours are less than or equal to max allowed
    require(_hours <= maxLock, "RealmLock: Must be below max allowed");

    // Lock
    locked[_realmId] = block.timestamp + (_hours * 3600);
  }

  function unlock(uint256 _realmId)
    external
    nonReentrant
    isRealmOwner(_realmId)
  {
    // Check if locked time has elapsed
    require(block.timestamp > locked[_realmId], "RealmLock: Cannot unlock yet");

    // Unlcok
    locked[_realmId] = 0;
  }

  function isUnlocked(uint256 _realmId) external view returns (bool) {
    return block.timestamp > locked[_realmId];
  }

  //=======================================
  // Admin
  //=======================================
  function updateMaxLock(uint256 _maxLock) external onlyAdmin {
    maxLock = _maxLock;
  }

  //=======================================
  // Internal
  //=======================================
  function _isRealmOwner(uint256 _realmId) internal view {
    require(
      REALM.ownerOf(_realmId) == msg.sender,
      "RealmLock: You do not own this Realm"
    );
  }
}

