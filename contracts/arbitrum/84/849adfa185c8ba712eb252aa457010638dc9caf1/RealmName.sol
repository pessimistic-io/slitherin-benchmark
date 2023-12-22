// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";

import "./ManagerModifier.sol";

contract RealmName is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;

  //=======================================
  // Uints
  //=======================================
  uint256 public timerDays;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => string) public names;
  mapping(uint256 => uint256) public timers;

  //=======================================
  // Events
  //=======================================
  event NameUpdated(uint256 realmId, string name, uint256 nextAvailableAt);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _realm, address _manager) ManagerModifier(_manager) {
    REALM = IRealm(_realm);

    timerDays = 365;
  }

  //=======================================
  // External
  //=======================================
  function updateName(uint256 _realmId, string memory _name)
    external
    nonReentrant
    whenNotPaused
  {
    // Check if sender owns Realm
    require(
      REALM.ownerOf(_realmId) == msg.sender,
      "RealmName: Must be Realm owner"
    );

    // Check timer
    require(
      block.timestamp > timers[_realmId],
      "RealmName: Can't update name yet"
    );

    // Set name
    names[_realmId] = _name;

    // Set timer
    timers[_realmId] = block.timestamp + (timerDays * 1 days);

    emit NameUpdated(_realmId, _name, timers[_realmId]);
  }

  //=======================================
  // Admin
  //=======================================
  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }

  function updateTimerDays(uint256 _value) external onlyAdmin {
    timerDays = _value;
  }

  function removeNames(
    uint256[] calldata _realmIds,
    string[] memory _names,
    uint256 _days
  ) external onlyAdmin {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256 realmId = _realmIds[j];
      string memory name = _names[j];

      // Set name
      names[realmId] = name;

      // Set timer
      timers[realmId] = block.timestamp + (_days * 1 days);

      emit NameUpdated(realmId, name, timers[realmId]);
    }
  }
}

