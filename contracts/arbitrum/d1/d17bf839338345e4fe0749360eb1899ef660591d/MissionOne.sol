// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ERC721A.sol";

import "./IAdventurerGateway.sol";
import "./IMissionOneStorage.sol";

import "./ManagerModifier.sol";

contract MissionOne is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IAdventurerGateway public immutable GATEWAY;
  IMissionOneStorage public immutable STORAGE;

  //=======================================
  // Uints
  //=======================================
  uint256 public missionLength;

  //=======================================
  // Events
  //=======================================
  event StartedMission(address addr, uint256 adventurerId);

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _gateway,
    address _missionOneStorage
  ) ManagerModifier(_manager) {
    GATEWAY = IAdventurerGateway(_gateway);
    STORAGE = IMissionOneStorage(_missionOneStorage);

    missionLength = 7 days;
  }

  //=======================================
  // External
  //=======================================
  function start(
    address[] calldata _addrs,
    uint256[] calldata _adventurerIds,
    bytes32[][] calldata _proofs
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      address addr = _addrs[j];
      uint256 adventurerId = _adventurerIds[j];

      // Check sender owns adventurer
      require(
        ERC721A(addr).ownerOf(adventurerId) == msg.sender,
        "MissionOne: You do not own Adventurer"
      );

      // Verify address
      GATEWAY.checkAddress(addr, _proofs[j]);

      // Set mission start time
      STORAGE.set(addr, adventurerId, missionLength);

      emit StartedMission(addr, adventurerId);
    }
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

  function updateMissionLength(uint256 _value) external onlyAdmin {
    missionLength = _value;
  }
}

