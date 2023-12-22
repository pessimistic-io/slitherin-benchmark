// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import { MerkleProof } from "./MerkleProof.sol";

import "./IAoV.sol";
import "./IAdventurerData.sol";
import "./IAnima.sol";
import "./IAdventurerGateway.sol";
import "./IAovLegacy.sol";
import "./IAovTranscendenceTimer.sol";

import "./ERC721A.sol";

import "./ManagerModifier.sol";

contract Transcendence is ManagerModifier, ReentrancyGuard, Pausable {
  using SafeERC20 for IAnima;

  //=======================================
  // Immutables
  //=======================================
  IAoV public immutable ADVENTURER;
  IAdventurerData public immutable ADVENTURER_DATA;
  IAnima public immutable ANIMA;
  IAdventurerGateway public immutable GATEWAY;
  IAovLegacy public immutable LEGACY;
  IAovTranscendenceTimer public immutable TIMER;
  address public VAULT;

  //=======================================
  // Uints
  //=======================================
  uint256 public animaBaseCost;
  uint256 public animaIncrement;
  uint256 public minArchetypeId;
  uint256 public maxArchetypeId;
  uint256 public maxProfession;
  uint256 public cooldown;

  //=======================================
  // Bytes
  //=======================================
  bytes32 public merkleRoot;

  //=======================================
  // Events
  //=======================================
  event Transcended(
    address addr,
    uint256 adventurerId,
    uint256 archetypeId,
    uint256 profession,
    uint256 cost
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _adventurer,
    address _adventurerData,
    address _anima,
    address _gateway,
    address _legacy,
    address _timer,
    address _vault,
    uint256 _animaBaseCost,
    uint256 _animaIncrement,
    bytes32 _merkleRoot
  ) ManagerModifier(_manager) {
    ADVENTURER = IAoV(_adventurer);
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    ANIMA = IAnima(_anima);
    GATEWAY = IAdventurerGateway(_gateway);
    LEGACY = IAovLegacy(_legacy);
    TIMER = IAovTranscendenceTimer(_timer);
    VAULT = _vault;

    animaBaseCost = _animaBaseCost;
    animaIncrement = _animaIncrement;

    merkleRoot = _merkleRoot;

    minArchetypeId = 7;
    maxArchetypeId = 24;
    maxProfession = 3;
    cooldown = 336;

    _pause();
  }

  //=======================================
  // External
  //=======================================
  function transcend(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds,
    bytes32[][] calldata _proofs,
    uint256[] calldata _archetypeIds,
    bytes32[][] calldata _archetypeProofs,
    uint256[] calldata _professions
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      address addr = _addresses[j];
      uint256 adventurerId = _adventurerIds[j];
      uint256 archetypeId = _archetypeIds[j];
      bytes32[] memory proof = _proofs[j];
      bytes32[] memory archetypeProof = _archetypeProofs[j];
      uint256 profession = _professions[j];

      // Set cooldown timer
      TIMER.set(addr, adventurerId, cooldown);

      // Check sender owns adventurer
      require(
        ERC721A(addr).ownerOf(adventurerId) == msg.sender,
        "Transcendence: You do not own Adventurer"
      );

      // Check profession is valid
      require(
        profession > 0 && profession <= maxProfession,
        "Transcendence: Profession not valid"
      );

      uint256 currentArchetype = _adventurerArchetype(addr, adventurerId);
      bool isSameArchetype = currentArchetype == archetypeId;

      // No need to check merkleProof is same archetype
      if (!isSameArchetype) {
        // Verify address
        bytes32 leaf = keccak256(
          abi.encodePacked(archetypeId, _adventurerClass(addr, adventurerId))
        );
        bool isValidLeaf = MerkleProof.verify(archetypeProof, merkleRoot, leaf);

        // Check if valid archetypeId for class
        require(
          isValidLeaf,
          "Transcendence: Variant class does not match your Adventurer class"
        );
      }

      // Verify token address
      GATEWAY.checkAddress(addr, proof);

      uint256 cost = _animaCost(addr, adventurerId);

      // Transfer Anima
      ANIMA.safeTransferFrom(msg.sender, VAULT, cost);

      // Track legacy
      LEGACY.chronicle(addr, adventurerId, currentArchetype, archetypeId);

      // Add to Level
      ADVENTURER_DATA.addToAov(addr, adventurerId, 0, 1);

      // Update Archetype if not the same
      if (!isSameArchetype) {
        ADVENTURER_DATA.updateAov(addr, adventurerId, 1, archetypeId);
      }

      // Update Profession
      ADVENTURER_DATA.updateAov(addr, adventurerId, 3, profession);

      emit Transcended(addr, adventurerId, archetypeId, profession, cost);
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

  function updateAnimaBaseCost(uint256 _value) external onlyAdmin {
    animaBaseCost = _value;
  }

  function updateAnimaIncrement(uint256 _value) external onlyAdmin {
    animaIncrement = _value;
  }

  function updateMinArchetypeId(uint256 _value) external onlyAdmin {
    minArchetypeId = _value;
  }

  function updateMaxArchetypeId(uint256 _value) external onlyAdmin {
    maxArchetypeId = _value;
  }

  function updateMaxProfession(uint256 _value) external onlyAdmin {
    maxProfession = _value;
  }

  function updateCooldown(uint256 _value) external onlyAdmin {
    cooldown = _value;
  }

  function updateMerkleRoot(bytes32 _value) external onlyAdmin {
    merkleRoot = _value;
  }

  //=======================================
  // Internal
  //=======================================
  function _adventurerClass(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    return ADVENTURER_DATA.aov(_addr, _adventurerId, 2);
  }

  function _animaCost(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    return
      animaBaseCost +
      (animaIncrement * (_adventurerLevel(_addr, _adventurerId) - 1));
  }

  function _adventurerLevel(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    return ADVENTURER_DATA.aov(_addr, _adventurerId, 0);
  }

  function _adventurerArchetype(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    return ADVENTURER_DATA.aov(_addr, _adventurerId, 1);
  }
}

