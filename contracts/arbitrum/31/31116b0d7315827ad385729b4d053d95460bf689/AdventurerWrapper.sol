// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./IERC721.sol";

import "./TraitConstants.sol";

import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";

import "./ManagerModifier.sol";

contract AdventurerWrapper is ManagerModifier, ReentrancyGuard, Pausable {
  //=======================================
  // Immutables
  //=======================================
  IAdventurerData public immutable ADVENTURER_DATA;
  IAdventurerGateway public immutable GATEWAY;

  //=======================================
  // Mappings
  //=======================================
  mapping(address => uint256) public classes;

  //=======================================
  // Events
  //=======================================
  event AdventurerWrapped(address addr, uint256 id);

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _adventurerData,
    address _gateway
  ) ManagerModifier(_manager) {
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    GATEWAY = IAdventurerGateway(_gateway);
  }

  function wrap(
    address[] calldata _addresses,
    uint256[] calldata _ids,
    bytes32[][] memory _proofs
  ) external nonReentrant whenNotPaused {
    for (uint256 index = 0; index < _ids.length; index++) {
      address addr = _addresses[index];
      uint256 id = _ids[index];
      uint256[] memory points = new uint256[](6);

      // Verify adventurer
      GATEWAY.checkAddress(addr, _proofs[index]);

      // Check sender owns the token
      require(
        IERC721(addr).ownerOf(id) == msg.sender,
        "AdventurerWrapper: You do not own Adventurer"
      );

      // Create data
      ADVENTURER_DATA.createFor(addr, id, points);

      // Initial level
      ADVENTURER_DATA.updateAov(addr, id, traits.ADVENTURER_TRAIT_LEVEL, 1);

      // Add class
      ADVENTURER_DATA.updateAov(
        addr,
        id,
        traits.ADVENTURER_TRAIT_CLASS,
        classes[addr]
      );

      emit AdventurerWrapped(addr, id);
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

  function configureClasses(
    address[] calldata _addresses,
    uint256[] calldata _classes
  ) external onlyAdmin {
    require(
      _addresses.length == _classes.length,
      "AdventurerWrapper: Mismatch array lengths"
    );

    for (uint256 index; index < _addresses.length; index++) {
      classes[_addresses[index]] = _classes[index];
    }
  }
}

