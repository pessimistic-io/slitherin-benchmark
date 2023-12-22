// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Pausable.sol";
import "./ERC721A.sol";
import "./IAoV.sol";
import "./IAdventurerData.sol";

import "./ManagerModifier.sol";

contract AovAdminMinter is ManagerModifier, Pausable {
  //=======================================
  // Immutables
  //=======================================
  IAoV public immutable ADVENTURER;
  IAdventurerData public immutable ADVENTURER_DATA;
  uint256 public immutable SUPPLY;

  //=======================================
  // Events
  //=======================================
  event Minted(address addr, uint256 id, uint256 archetype);

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _adventurer,
    address _adventurerData,
    uint256 _supply
  ) ManagerModifier(_manager) {
    ADVENTURER = IAoV(_adventurer);
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    SUPPLY = _supply;
  }

  function mint(address _owner, uint256[6] calldata _archetypes)
    external
    whenNotPaused
    onlyAdmin
  {
    // Check total supply
    require(
      ERC721A(address(ADVENTURER)).totalSupply() < SUPPLY,
      "AovAdminMinter: Total supply reached"
    );

    for (uint256 index = 0; index < _archetypes.length; index++) {
      // Get amount per archetype
      uint256 amount = _archetypes[index];
      uint256 archetype = index + 1;

      // Check amount is not zero
      if (amount == 0) continue;

      // Mint
      uint256 startTokenId = ADVENTURER.mintFor(_owner, amount);

      for (uint256 h = 0; h < amount; h++) {
        // Create data
        ADVENTURER_DATA.createFor(address(ADVENTURER), startTokenId, archetype);

        emit Minted(address(ADVENTURER), startTokenId, archetype);

        startTokenId++;
      }
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
}

