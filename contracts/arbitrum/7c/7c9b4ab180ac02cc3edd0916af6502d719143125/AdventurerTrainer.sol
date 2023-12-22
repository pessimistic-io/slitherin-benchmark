// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

import "./IAdventurerTrainerStorage.sol";
import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";
import "./IParticle.sol";

import "./ManagerModifier.sol";

contract AdventurerTrainer is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IParticle;

  //=======================================
  // Immutables
  //=======================================
  IAdventurerTrainerStorage public immutable STORAGE;
  IAdventurerData public immutable ADVENTURER_DATA;
  IAdventurerGateway public immutable GATEWAY;
  IParticle public immutable PARTICLE;
  address public immutable VAULT;
  uint256 public immutable LEVEL_ID;

  //=======================================
  // Uints
  //=======================================
  uint256 public trainingCost;
  uint256 public maxAmountForTraits;

  //=======================================
  // Events
  //=======================================
  event Trained(
    address addr,
    uint256 adventurerId,
    uint256 traitId,
    uint256 traitAmount,
    uint256 trainingCost
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _traitStorage,
    address _adventurerData,
    address _gateway,
    address _token,
    address _vault
  ) ManagerModifier(_manager) {
    STORAGE = IAdventurerTrainerStorage(_traitStorage);
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    GATEWAY = IAdventurerGateway(_gateway);
    PARTICLE = IParticle(_token);
    VAULT = _vault;

    LEVEL_ID = 0;

    trainingCost = 0.025 ether;
    maxAmountForTraits = 6;
  }

  //=======================================
  // External
  //=======================================

  function train(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds,
    bytes32[][] memory _proofs,
    uint256[][] calldata _traitIds,
    uint256[][] calldata _traitAmounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      address addr = _addresses[j];
      uint256 adventurerId = _adventurerIds[j];
      uint256[] memory traitIds = _traitIds[j];
      uint256[] memory traitAmounts = _traitAmounts[j];

      // Check sender owns adventurer
      require(
        ERC721(addr).ownerOf(adventurerId) == msg.sender,
        "AdventurerTrainer: You do not own Adventurer"
      );

      // Verify adventurer
      GATEWAY.checkAddress(addr, _proofs[j]);

      // Set epoch
      STORAGE.setEpoch(addr, adventurerId);

      uint256 total;

      for (uint256 i = 0; i < traitIds.length; i++) {
        // Check if trait amount is zero
        if (traitAmounts[i] == 0) continue;

        // Check trait ID is valid
        require(
          traitIds[i] >= 2 && traitIds[i] <= 7,
          "AdventurerTrainer: Trait ID is not valid"
        );

        // Add to total
        total += traitAmounts[i];

        // Get training cost
        uint256 cost = _getTrainingCost(addr, adventurerId, traitAmounts[i]);

        // Transfer token to vault
        PARTICLE.safeTransferFrom(msg.sender, VAULT, cost);

        // Add to base trait
        ADVENTURER_DATA.addToBase(
          addr,
          adventurerId,
          traitIds[i],
          traitAmounts[i]
        );

        emit Trained(addr, adventurerId, traitIds[i], traitAmounts[i], cost);
      }

      // Check if max amount exceeded
      require(
        total <= maxAmountForTraits,
        "AdventurerTrainer: Max amount for Traits exceeded"
      );
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

  function updateTrainingCost(uint256 _value) external onlyAdmin {
    trainingCost = _value;
  }

  function updateMaxAmountForTraits(uint256 _value) external onlyAdmin {
    maxAmountForTraits = _value;
  }

  //=======================================
  // Internal
  //=======================================
  function _getTrainingCost(
    address _addr,
    uint256 _adventurerId,
    uint256 _traitAmount
  ) internal view returns (uint256) {
    // Calculate cost based on transcendence level
    uint256 cost = ADVENTURER_DATA.aov(_addr, _adventurerId, LEVEL_ID) *
      trainingCost *
      _traitAmount;

    return cost;
  }
}

