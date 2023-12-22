// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ERC721A.sol";
import "./IAoV.sol";
import "./IAdventurerData.sol";
import "./IERC721Bound.sol";

import "./ManagerModifier.sol";

contract AovPublicMinter is ManagerModifier, ReentrancyGuard, Pausable {
  //=======================================
  // Immutables
  //=======================================
  IAoV public immutable ADVENTURER;
  IAdventurerData public immutable ADVENTURER_DATA;
  IERC721Bound public immutable BOUND;
  address public immutable VAULT;
  uint256 public immutable SUPPLY;

  //=======================================
  // Uints
  //=======================================
  uint256 public price;
  uint256 public maxMintable;

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
    address _bound,
    address _vault,
    uint256 _price,
    uint256 _maxMintable
  ) ManagerModifier(_manager) {
    ADVENTURER = IAoV(_adventurer);
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    BOUND = IERC721Bound(_bound);
    VAULT = _vault;
    SUPPLY = 10000;

    price = _price;
    maxMintable = _maxMintable;
  }

  function mint(uint256[6] calldata _archetypes)
    external
    payable
    nonReentrant
    whenNotPaused
  {
    // Add up total to mint
    uint256 total = _archetypes[0] +
      _archetypes[1] +
      _archetypes[2] +
      _archetypes[3] +
      _archetypes[4] +
      _archetypes[5];

    // Check if total is less than max mintable per transaction
    require(
      total <= maxMintable,
      "AovPublicMinter: Max mintable per transaction exceeded"
    );

    // Check total supply
    require(
      ERC721A(address(ADVENTURER)).totalSupply() < SUPPLY,
      "AovPublicMinter: Total supply reached"
    );

    // Check ETH
    require(msg.value == price * total, "AovPublicMinter: Not enough ETH");

    for (uint256 index = 0; index < _archetypes.length; index++) {
      // Get amount per archetype
      uint256 amount = _archetypes[index];
      uint256 archetype = index + 1;

      // Check amount is not zero
      if (amount == 0) continue;

      // Mint
      uint256 startTokenId = ADVENTURER.mintFor(msg.sender, amount);

      for (uint256 h = 0; h < amount; h++) {
        // Create data
        ADVENTURER_DATA.createFor(address(ADVENTURER), startTokenId, archetype);

        // Unbind
        BOUND.unbind(address(ADVENTURER), startTokenId);

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

  function withdraw() external onlyAdmin {
    payable(VAULT).transfer(address(this).balance);
  }
}

