// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";

import "./ERC721A.sol";

import "./IQuestTimer.sol";
import "./IAnima.sol";
import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";
import "./IRand.sol";

import "./ManagerModifier.sol";

contract QuestManagerV3 is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IAnima;

  //=======================================
  // Immutables
  //=======================================
  IQuestTimer public immutable QUEST_TIMER;
  IAnima public immutable ANIMA;
  IAdventurerData public immutable ADVENTURER_DATA;
  IAdventurerGateway public immutable GATEWAY;
  address public immutable VAULT;
  uint256 public immutable XP_ID;
  uint256 public immutable LEVEL_ID;

  //=======================================
  // Interfaces
  //=======================================
  IRand public randomizer;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) public questTraits;

  //=======================================
  // Uints
  //=======================================
  uint256 public cooldown;
  uint256 public xpAdded;
  uint256 public traitBase;
  uint256 public animaBaseCost;

  //=======================================
  // Arrays
  //========================================
  uint256[] public bonusProbability = [60, 90, 100];
  uint256[] public traitBonuses = [0, 1, 2];

  //=======================================
  // Events
  //=======================================
  event Quested(
    address addr,
    uint256 adventurerId,
    uint256 questId,
    uint256 animaCost,
    uint256 xpAdded,
    uint256 traitId,
    uint256 traitAdded,
    uint256 traitBonus
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _timer,
    address _anima,
    address _data,
    address _vault,
    address _gateway,
    address _rand,
    uint256 _cooldown
  ) ManagerModifier(_manager) {
    QUEST_TIMER = IQuestTimer(_timer);
    ANIMA = IAnima(_anima);
    ADVENTURER_DATA = IAdventurerData(_data);
    VAULT = _vault;
    GATEWAY = IAdventurerGateway(_gateway);
    XP_ID = 0;
    LEVEL_ID = 0;

    randomizer = IRand(_rand);

    cooldown = _cooldown;
    xpAdded = 1;
    traitBase = 1;
    animaBaseCost = 100000000000000000;

    questTraits[0] = 2;
    questTraits[1] = 3;
    questTraits[2] = 4;
    questTraits[3] = 5;
    questTraits[4] = 6;
    questTraits[5] = 7;
  }

  //=======================================
  // External
  //=======================================
  function quest(
    address[] calldata _addrs,
    uint256[] calldata _adventurerIds,
    bytes32[][] calldata _proofs,
    uint256 _questId
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      address addr = _addrs[j];
      uint256 adventurerId = _adventurerIds[j];

      // Verify address
      GATEWAY.checkAddress(addr, _proofs[j]);

      // Check sender owns adventurer
      require(
        ERC721A(addr).ownerOf(adventurerId) == msg.sender,
        "QuestManager: You do not own Adventurer"
      );

      // Set quest tracker
      QUEST_TIMER.set(addr, adventurerId, 1, cooldown);

      // Add XP
      ADVENTURER_DATA.addToBase(addr, adventurerId, XP_ID, xpAdded);

      // Get trait amount
      uint256 traitBonus = _getTraitBonus(adventurerId);
      uint256 traitAmount = traitBase + traitBonus;

      // Add Trait
      ADVENTURER_DATA.addToBase(
        addr,
        adventurerId,
        questTraits[_questId],
        traitAmount
      );

      // Get anima cost
      uint256 animaCost = _animaCost(addr, adventurerId);

      // Transfer Anima to vault
      ANIMA.safeTransferFrom(msg.sender, VAULT, animaCost);

      emit Quested(
        addr,
        adventurerId,
        _questId,
        animaCost,
        xpAdded,
        questTraits[_questId],
        traitAmount,
        traitBonus
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

  function updateCooldown(uint256 _value) external onlyAdmin {
    cooldown = _value;
  }

  function updateXpAdded(uint256 _value) external onlyAdmin {
    xpAdded = _value;
  }

  function updateBonusProbability(uint256[] calldata _value)
    external
    onlyAdmin
  {
    bonusProbability = _value;
  }

  function updateTraitBonuses(uint256[] calldata _value) external onlyAdmin {
    traitBonuses = _value;
  }

  function updateAnimaCost(uint256 _value) external onlyAdmin {
    animaBaseCost = _value;
  }

  //=======================================
  // Internal
  //=======================================
  function _animaCost(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    // Calculate anima based on transcendence level
    uint256 anima = ADVENTURER_DATA.aov(_addr, _adventurerId, LEVEL_ID) *
      animaBaseCost;

    return anima;
  }

  function _traitAmount(uint256 _salt) internal view returns (uint256) {
    return traitBase + _getTraitBonus(_salt);
  }

  function _getTraitBonus(uint256 _salt) internal view returns (uint256) {
    uint256 rand = uint256(
      keccak256(
        abi.encodePacked(
          block.number,
          block.timestamp,
          randomizer.retrieve(_salt)
        )
      )
    ) % 100;

    uint256 j;

    for (j; j < bonusProbability.length; j++) {
      if (rand <= bonusProbability[j]) {
        break;
      }
    }

    return traitBonuses[j];
  }
}

