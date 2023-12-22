// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Pausable.sol";
import "./ERC721A.sol";
import "./IAoV.sol";
import "./IAdventurerData.sol";
import "./IERC721Bound.sol";

import "./ManagerModifier.sol";

contract AovAdminMinter is ManagerModifier, Pausable {
  //=======================================
  // Immutables
  //=======================================
  IAoV public immutable ADVENTURER;
  IAdventurerData public immutable ADVENTURER_DATA;
  IERC721Bound public immutable BOUND;
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
    address _bound,
    address _adventurerData,
    uint256 _supply
  ) ManagerModifier(_manager) {
    ADVENTURER = IAoV(_adventurer);
    BOUND = IERC721Bound(_bound);
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    SUPPLY = _supply;
  }

  function mint(
    address[] calldata _owners,
    bool[] calldata _unbind,
    uint256[][] calldata _archetypes
  ) external whenNotPaused onlyAdmin {
    for (uint256 j = 0; j < _owners.length; j++) {
      address owner = _owners[j];
      bool unbind = _unbind[j];
      uint256[] memory archetypes = _archetypes[j];

      // Check total supply
      require(
        ERC721A(address(ADVENTURER)).totalSupply() < SUPPLY,
        "AovAdminMinter: Total supply reached"
      );

      for (uint256 index = 0; index < archetypes.length; index++) {
        // Get amount per archetype
        uint256 amount = archetypes[index];
        uint256 archetype = index + 1;

        // Check amount is not zero
        if (amount == 0) continue;

        // Mint
        uint256 startTokenId = ADVENTURER.mintFor(owner, amount);

        for (uint256 h = 0; h < amount; h++) {
          // Create data
          ADVENTURER_DATA.createFor(
            address(ADVENTURER),
            startTokenId,
            archetype
          );

          if (unbind) {
            BOUND.unbind(address(ADVENTURER), startTokenId);
          }

          emit Minted(address(ADVENTURER), startTokenId, archetype);

          startTokenId++;
        }
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

