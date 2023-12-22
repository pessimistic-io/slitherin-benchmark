// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

import "./IBattleVersusStorage.sol";
import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";
import "./IParticle.sol";
import "./IAnima.sol";

import "./IRand.sol";

import "./ManagerModifier.sol";

contract BattleVersus is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IAnima;
  using SafeERC20 for IParticle;

  //=======================================
  // Immutables
  //=======================================
  IBattleVersusStorage public immutable STORAGE;
  IAdventurerData public immutable ADVENTURER_DATA;
  IAdventurerGateway public immutable GATEWAY;
  IParticle public immutable PARTICLE;
  IAnima public immutable ANIMA;
  address public immutable VAULT;
  uint256 public immutable PRECISION;
  uint256 public immutable UPPER;
  uint256 public immutable MID;
  uint256 public immutable MAX_BONUS;
  uint256 public immutable XP_ID;

  //=======================================
  // Interface
  //=======================================
  IRand public randomizer;

  //=======================================
  // Uints
  //=======================================
  uint256 public fightId;
  uint256 public attackerCooldown;
  uint256 public opponentCooldown;
  uint256 public animaBaseReward;
  uint256 public animaPassiveRewardPercentage;
  uint256 public professionBonus;
  uint256 public particleBaseCost;
  uint256 public particleCostPercentage;
  uint256 public xpReward;

  //=======================================
  // Events
  //=======================================
  event FightStarted(
    uint256 fightId,
    address contender1Addr,
    uint256 contender1Id,
    address contender2Addr,
    uint256 contender2Id
  );
  event ContenderRoll(
    uint256 fightId,
    address winnerAddr,
    uint256 winnerId,
    uint256 traitId,
    uint256 probability,
    uint256 difference
  );
  event TokensDistributed(
    uint256 fightId,
    address addr,
    uint256 adventureId,
    uint256 anima,
    uint256 animaBonus,
    uint256 particleCost
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _storage,
    address _data,
    address _gateway,
    address _particle,
    address _anima,
    address _vault,
    address _rand,
    uint256 _attackerCooldown,
    uint256 _opponentCooldown
  ) ManagerModifier(_manager) {
    STORAGE = IBattleVersusStorage(_storage);
    ADVENTURER_DATA = IAdventurerData(_data);
    GATEWAY = IAdventurerGateway(_gateway);
    PARTICLE = IParticle(_particle);
    ANIMA = IAnima(_anima);
    VAULT = _vault;

    PRECISION = 10**9;
    UPPER = 98;
    MID = 49;
    MAX_BONUS = 294;
    XP_ID = 1;

    randomizer = IRand(_rand);

    attackerCooldown = _attackerCooldown;
    opponentCooldown = _opponentCooldown;

    animaBaseReward = 300000000000000000;
    animaPassiveRewardPercentage = 10;

    professionBonus = 10000000000000000;

    particleBaseCost = 25000000000000000;

    xpReward = 1;
  }

  //=======================================
  // External
  //=======================================

  function fight(
    address _addr,
    uint256 _adventurerId,
    bytes32[] calldata _proof,
    address _oppAddr,
    uint256 _oppAdventurerId,
    bytes32[] calldata _oppProof
  ) external nonReentrant whenNotPaused {
    // Check if same token
    if (_addr == _oppAddr) {
      require(
        _adventurerId != _oppAdventurerId,
        "BattleVersus: Cannot battle same Adventurer"
      );
    }

    // Check sender owns adventurer
    require(
      ERC721(_addr).ownerOf(_adventurerId) == msg.sender,
      "BattleVersus: You do not own Adventurer"
    );

    // Verify adventurer
    GATEWAY.checkAddress(_addr, _proof);

    // Verify opponent
    GATEWAY.checkAddress(_oppAddr, _oppProof);

    // Increment fight count
    fightId++;

    emit FightStarted(
      fightId,
      _addr,
      _adventurerId,
      _oppAddr,
      _oppAdventurerId
    );

    // Begin battle
    _beginVersusBattle(_addr, _adventurerId, _oppAddr, _oppAdventurerId);

    // Set attacker cooldown
    STORAGE.setAttackerCooldown(_addr, _adventurerId, attackerCooldown);

    // Set opponent cooldown
    STORAGE.setOpponentCooldown(_oppAddr, _oppAdventurerId, opponentCooldown);
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

  function updateAttackerCooldown(uint256 _value) external onlyAdmin {
    attackerCooldown = _value;
  }

  function updateOpponentCooldown(uint256 _value) external onlyAdmin {
    opponentCooldown = _value;
  }

  function updateAnimaBaseRewards(uint256 _value) external onlyAdmin {
    animaBaseReward = _value;
  }

  function updateAnimaPassiveRewardPercentage(uint256 _value)
    external
    onlyAdmin
  {
    animaPassiveRewardPercentage = _value;
  }

  function updateProfessionBonus(uint256 _value) external onlyAdmin {
    professionBonus = _value;
  }

  function updateParticleBaseCost(uint256 _value) external onlyAdmin {
    particleBaseCost = _value;
  }

  function updateParticleCostPercentage(uint256 _value) external onlyAdmin {
    particleCostPercentage = _value;
  }

  function updateXpReward(uint256 _value) external onlyAdmin {
    xpReward = _value;
  }

  function updateRand(address _value) external onlyAdmin {
    randomizer = IRand(_value);
  }

  //=======================================
  // Internal
  //=======================================
  function _beginVersusBattle(
    address _contender1Addr,
    uint256 _contender1Id,
    address _contender2Addr,
    uint256 _contender2Id
  ) internal {
    uint256 contender1Wins;
    uint256 contender2Wins;
    uint256 contender1Bonus;

    for (uint256 j = 2; j < 8; j++) {
      uint256 contender1Trait = (ADVENTURER_DATA.base(
        _contender1Addr,
        _contender1Id,
        j
      ) + 1);
      uint256 contender2Trait = (ADVENTURER_DATA.base(
        _contender2Addr,
        _contender2Id,
        j
      ) + 1);

      if (contender1Trait < contender2Trait) {
        // Contender1 is weaker
        (bool won, uint256 probability) = _fight(
          contender2Trait,
          contender1Trait,
          j
        );

        // Get difference between strong and weak probability
        uint256 diff = 1 + (UPPER - probability) - probability;

        if (won) {
          contender1Wins += diff;
          contender1Bonus += MID - probability;
        } else {
          contender2Wins += diff;
        }

        emit ContenderRoll(
          fightId,
          won ? _contender1Addr : _contender2Addr,
          won ? _contender1Id : _contender2Id,
          j,
          won ? probability : UPPER - probability,
          diff
        );
      } else {
        // Contender2 is weaker
        (bool won, uint256 probability) = _fight(
          contender1Trait,
          contender2Trait,
          j
        );

        // Get difference between strong and weak probability
        uint256 diff = 1 + (UPPER - probability) - probability;

        if (won) {
          contender2Wins += diff;
        } else {
          contender1Wins += diff;
        }

        emit ContenderRoll(
          fightId,
          won ? _contender2Addr : _contender1Addr,
          won ? _contender2Id : _contender1Id,
          j,
          won ? probability : UPPER - probability,
          diff
        );
      }
    }

    _results(
      _contender1Addr,
      _contender1Id,
      _contender2Addr,
      _contender2Id,
      contender1Wins,
      contender2Wins,
      contender1Bonus
    );
  }

  function _fight(
    uint256 _strongerTrait,
    uint256 _weakerTrait,
    uint256 _salt
  ) internal view returns (bool, uint256) {
    _strongerTrait = _strongerTrait * PRECISION;
    _weakerTrait = _weakerTrait * PRECISION;

    uint256 minScore = (_strongerTrait / 2);
    uint256 probability;

    // Check if weaker trait is too weak
    if (_weakerTrait < minScore) {
      probability = 0;
    } else {
      // Normalize
      probability =
        (((_weakerTrait - minScore) * PRECISION) /
          ((_strongerTrait - minScore))) *
        MID;

      // Remove precision
      probability = probability / PRECISION;
    }

    // Return true if fight was won by _weakerTrait
    if (_getRand(_strongerTrait + _weakerTrait + _salt) <= probability) {
      return (true, probability);
    }

    // Return false if fight was won by _strongerTrait
    return (false, probability);
  }

  function _results(
    address _contender1Addr,
    uint256 _contender1Id,
    address _contender2Addr,
    uint256 _contender2Id,
    uint256 _contender1Wins,
    uint256 _contender2Wins,
    uint256 _contender1Bonus
  ) internal {
    uint256 particleCost = _getParticleCost(_contender1Addr, _contender1Id);
    uint256 anima;

    // Transfer Particle to vault
    PARTICLE.safeTransferFrom(msg.sender, VAULT, particleCost);

    if (_contender1Wins > _contender2Wins) {
      // Calculate anima
      anima = _getAnima(_contender1Addr, _contender1Id);

      // Calculate bonus
      uint256 animaBonus = _getAnimaBonus(anima, _contender1Bonus);

      // Mint Anima
      ANIMA.mintFor(
        ERC721(_contender1Addr).ownerOf(_contender1Id),
        anima + animaBonus
      );

      // Update wins
      STORAGE.updateWins(_contender2Addr, _contender2Id, 1);

      // Update losses
      STORAGE.updateLosses(_contender1Addr, _contender1Id, 1);

      emit TokensDistributed(
        fightId,
        _contender1Addr,
        _contender1Id,
        anima,
        animaBonus,
        particleCost
      );
    } else {
      // Calculate anima
      anima =
        (_getAnima(_contender2Addr, _contender2Id) / 100) *
        animaPassiveRewardPercentage;

      // Mint Anima
      ANIMA.mintFor(ERC721(_contender2Addr).ownerOf(_contender2Id), anima);

      // Update wins
      STORAGE.updateWins(_contender2Addr, _contender2Id, 1);

      // Update losses
      STORAGE.updateLosses(_contender1Addr, _contender1Id, 1);

      emit TokensDistributed(
        fightId,
        _contender2Addr,
        _contender2Id,
        anima,
        0,
        particleCost
      );
    }

    // Add XP
    ADVENTURER_DATA.addToBase(_contender1Addr, _contender1Id, XP_ID, xpReward);
  }

  function _getRand(uint256 _salt) internal view returns (uint256) {
    return
      uint256(
        keccak256(
          abi.encodePacked(
            block.number,
            block.timestamp,
            randomizer.retrieve(_salt)
          )
        )
      ) % 100;
  }

  function _getAnima(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    // Calculate anima based on transcendence level
    uint256 anima = ADVENTURER_DATA.aov(_addr, _adventurerId, 0) *
      animaBaseReward;

    // Check if profession is Zealot
    if (ADVENTURER_DATA.aov(_addr, _adventurerId, 3) == 2) {
      anima += professionBonus;
    }

    return anima;
  }

  function _getAnimaBonus(uint256 _anima, uint256 _diff)
    internal
    view
    returns (uint256)
  {
    uint256 normalized = (((_diff - 0) * PRECISION) / (MAX_BONUS - 0)) * 100;

    return ((_anima / 100) * normalized) / PRECISION;
  }

  function _getParticleCost(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    // Calculate particle cost based on transcendence level
    return ADVENTURER_DATA.aov(_addr, _adventurerId, 0) * particleBaseCost;
  }
}

