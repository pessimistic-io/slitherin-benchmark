// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

import "./IBattleVersusStorageV2.sol";
import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";
import "./IParticle.sol";
import "./IAnima.sol";
import "./IBattleEntry.sol";

import "./ManagerModifier.sol";
import "./Random.sol";

contract BattleVersusV2 is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IAnima;
  using SafeERC20 for IParticle;

  //=======================================
  // Immutables
  //=======================================
  IBattleVersusStorageV2 public immutable STORAGE;
  IAdventurerData public immutable ADVENTURER_DATA;
  IAdventurerGateway public immutable GATEWAY;
  IParticle public immutable PARTICLE;
  IAnima public immutable ANIMA;
  IBattleEntry public immutable BATTLE_ENTRY;
  address public immutable VAULT;
  uint256 public immutable PRECISION;
  uint256 public immutable UPPER;
  uint256 public immutable MID;
  uint256 public immutable MAX_BONUS;
  uint256 public immutable XP_ID;
  uint256 public immutable MIN_SCORE_RANGE;

  //=======================================
  // Uints
  //=======================================
  uint256 public fightId;
  uint256 public animaBaseReward;
  uint256 public animaPassiveRewardPercentage;
  uint256 public particleBaseCost;
  uint256 public particleCostPercentage;
  uint256 public xpReward;
  uint256 public outOfRangeDivider;
  uint256 public attackerRewardDivider;
  uint256 public bonusMultiplier;

  //=======================================
  // Events
  //=======================================
  event FightStarted(
    uint256 fightId,
    address attackerAddr,
    uint256 attackerId,
    address opponentAddr,
    uint256 opponentId,
    uint256 particleCost
  );
  event ContenderRoll(
    uint256 fightId,
    address winnerAddr,
    uint256 winnerId,
    uint256 traitId,
    uint256 probability,
    uint256 animaReward,
    uint256 animaBonus,
    uint256 attackerReward
  );
  event OverallWinner(
    uint256 fightId,
    address addr,
    uint256 adventureId,
    uint256 anima
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
    address _battleEntry,
    address _vault
  ) ManagerModifier(_manager) {
    STORAGE = IBattleVersusStorageV2(_storage);
    ADVENTURER_DATA = IAdventurerData(_data);
    GATEWAY = IAdventurerGateway(_gateway);
    PARTICLE = IParticle(_particle);
    ANIMA = IAnima(_anima);
    BATTLE_ENTRY = IBattleEntry(_battleEntry);
    VAULT = _vault;

    PRECISION = 10 ** 9;
    UPPER = 98;
    MID = 49;
    MAX_BONUS = 49;
    XP_ID = 1;
    MIN_SCORE_RANGE = 2;

    animaBaseReward = 0.2 ether;
    animaPassiveRewardPercentage = 10;

    particleBaseCost = 0.025 ether;

    xpReward = 1;
    outOfRangeDivider = 10;
    attackerRewardDivider = 2;
    bonusMultiplier = 12;
  }

  struct FightData {
    uint256 totalParticle;
    uint256 totalAnima;
    uint256 particleCost;
    uint256 attackerReward;
    uint256 opponentReward;
    uint256 randomBase;
  }

  //=======================================
  // External
  //=======================================
  function fight(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds,
    bytes32[][] memory _proofs,
    address[] calldata _oppAddresses,
    uint256[] calldata _oppAdventurerIds,
    bytes32[][] memory _oppProofs
  ) external nonReentrant whenNotPaused {
    FightData memory fightData;
    fightData.randomBase = Random.startRandomBase(
      uint256(uint160(msg.sender)),
      fightId
    );
    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      address addr = _addresses[j];
      uint256 adventurerId = _adventurerIds[j];
      address oppAddr = _oppAddresses[j];
      uint256 oppAdventurerId = _oppAdventurerIds[j];

      // Check if same token
      if (addr == oppAddr) {
        require(
          adventurerId != oppAdventurerId,
          "BattleVersusV2: Cannot battle same Adventurer"
        );
      }

      // Check sender owns adventurer
      require(
        ERC721(addr).ownerOf(adventurerId) == msg.sender,
        "BattleVersusV2: You do not own Adventurer"
      );

      // Verify adventurer
      GATEWAY.checkAddress(addr, _proofs[j]);

      // Verify opponent
      GATEWAY.checkAddress(oppAddr, _oppProofs[j]);

      // Check if opponent is eligible
      require(
        BATTLE_ENTRY.isEligible(oppAddr, oppAdventurerId),
        "BattleVersusV2: Opponent is not eligible"
      );

      // Set entry
      BATTLE_ENTRY.set(addr, adventurerId);

      // Increment fight count
      fightId++;

      // Calculate particle cost
      fightData.particleCost = _getParticleCost(addr, adventurerId);
      fightData.totalParticle += fightData.particleCost;

      emit FightStarted(
        fightId,
        addr,
        adventurerId,
        oppAddr,
        oppAdventurerId,
        fightData.particleCost
      );

      // Begin battle
      (
        fightData.attackerReward,
        fightData.opponentReward,
        fightData.randomBase
      ) = _beginVersusBattle(
        addr,
        adventurerId,
        oppAddr,
        oppAdventurerId,
        fightData.randomBase
      );

      // Add attacker rewards to total anima
      fightData.totalAnima += fightData.attackerReward;

      // Mint opponent anima rewards for opponent
      ANIMA.mintFor(
        ERC721(oppAddr).ownerOf(oppAdventurerId),
        fightData.opponentReward
      );

      // Set attacker epoch
      STORAGE.setAttackerEpoch(addr, adventurerId);
    }

    // Transfer Particle to vault
    PARTICLE.safeTransferFrom(msg.sender, VAULT, fightData.totalParticle);

    // Mint attacker anima rewards
    ANIMA.mintFor(msg.sender, fightData.totalAnima);
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

  function updateAnimaBaseRewards(uint256 _value) external onlyAdmin {
    animaBaseReward = _value;
  }

  function updateAnimaPassiveRewardPercentage(
    uint256 _value
  ) external onlyAdmin {
    animaPassiveRewardPercentage = _value;
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

  function updateOutOfRangeDivider(uint256 _value) external onlyAdmin {
    outOfRangeDivider = _value;
  }

  function updateAttackerRewardDivider(uint256 _value) external onlyAdmin {
    attackerRewardDivider = _value;
  }

  function updateBonusMultiplier(uint256 _value) external onlyAdmin {
    bonusMultiplier = _value;
  }

  //=======================================
  // Internal
  //=======================================

  struct BattleData {
    address attackerAddr;
    uint256 attackerId;
    address opponentAddr;
    uint256 opponentId;
    uint256 baseAttackerAnima;
    uint256 baseOpponentAnima;
    uint256 attackerReward;
    uint256 opponentReward;
    uint256 randomBase;
    uint256 wins;
  }

  struct TraitBattleData {
    uint256 traitId;
    uint256 attackerTrait;
    uint256 opponentTrait;
    uint256 attackerAnima;
    uint256 opponentAnima;
    uint256 roll;
    uint64 probability;
    bool won;
    bool withinRange;
    bool hasBonus;
  }

  function _beginVersusBattle(
    address _attackerAddr,
    uint256 _attackerId,
    address _opponentAddr,
    uint256 _opponentId,
    uint256 _randomBase
  ) internal returns (uint256, uint256, uint256) {
    BattleData memory battleData;
    battleData.attackerAddr = _attackerAddr;
    battleData.attackerId = _attackerId;
    battleData.opponentAddr = _opponentAddr;
    battleData.opponentId = _opponentId;
    battleData.randomBase = _randomBase;

    // Calculate anima for contender 1
    battleData.baseAttackerAnima = _getAnima(_attackerAddr, _attackerId);

    // Calculate anima for contender 2
    battleData.baseOpponentAnima =
      (_getAnima(_opponentAddr, _opponentId) / 100) *
      animaPassiveRewardPercentage;

    TraitBattleData memory traitBattleData;

    for (uint8 traitId = 2; traitId < 8; traitId++) {
      traitBattleData.traitId = traitId;
      traitBattleData.attackerTrait = (ADVENTURER_DATA.base(
        _attackerAddr,
        _attackerId,
        traitId
      ) + 1);
      traitBattleData.opponentTrait = (ADVENTURER_DATA.base(
        _opponentAddr,
        _opponentId,
        traitId
      ) + 1);

      // Begin trait battle
      (battleData.randomBase, traitBattleData) = _traitBattle(
        battleData,
        traitBattleData
      );

      // Add attacker anima rewards
      battleData.attackerReward += traitBattleData.attackerAnima;

      // Add anima rewards
      battleData.opponentReward += traitBattleData.opponentAnima;
      if (traitBattleData.won) {
        battleData.wins++;
      }
    }

    if (battleData.wins > 3) {
      battleData.attackerReward += battleData.baseAttackerAnima;

      ADVENTURER_DATA.addToBase(_attackerAddr, _attackerId, XP_ID, xpReward);

      emit OverallWinner(
        fightId,
        _attackerAddr,
        _attackerId,
        battleData.baseAttackerAnima
      );
    } else {
      battleData.opponentReward += battleData.baseOpponentAnima;

      emit OverallWinner(
        fightId,
        _opponentAddr,
        _opponentId,
        battleData.baseOpponentAnima
      );
    }

    return (
      battleData.attackerReward,
      battleData.opponentReward,
      battleData.randomBase
    );
  }

  function _traitBattle(
    BattleData memory battleData,
    TraitBattleData memory traitBattleData
  ) internal returns (uint256, TraitBattleData memory) {
    (traitBattleData.roll, battleData.randomBase) = Random.getNextRandom(
      battleData.randomBase,
      100
    );

    if (traitBattleData.attackerTrait < traitBattleData.opponentTrait) {
      // Attacker is weaker
      (
        traitBattleData.won,
        traitBattleData.withinRange,
        traitBattleData.probability
      ) = _fight(
        traitBattleData.opponentTrait,
        traitBattleData.attackerTrait,
        traitBattleData.roll
      );

      if (traitBattleData.won) {
        traitBattleData.attackerAnima = _calculateAnima(
          traitBattleData,
          battleData.attackerAddr,
          battleData.attackerId,
          battleData.baseAttackerAnima,
          true,
          0,
          true
        );

        traitBattleData.opponentAnima = 0;

        return (battleData.randomBase, traitBattleData);
      } else {
        // Calculate attacker rewards
        // Attacker gets 50% rewards for taking the risk
        traitBattleData.attackerAnima =
          battleData.baseAttackerAnima /
          attackerRewardDivider;

        traitBattleData.opponentAnima = _calculateAnima(
          traitBattleData,
          battleData.opponentAddr,
          battleData.opponentId,
          battleData.baseOpponentAnima,
          false,
          traitBattleData.attackerAnima,
          true
        );

        return (battleData.randomBase, traitBattleData);
      }
    } else {
      // Opponent is weaker
      (
        traitBattleData.won,
        traitBattleData.withinRange,
        traitBattleData.probability
      ) = _fight(
        traitBattleData.attackerTrait,
        traitBattleData.opponentTrait,
        traitBattleData.roll
      );

      traitBattleData.won = !traitBattleData.won;

      if (!traitBattleData.won) {
        traitBattleData.attackerAnima = 0;

        traitBattleData.opponentAnima = _calculateAnima(
          traitBattleData,
          battleData.opponentAddr,
          battleData.opponentId,
          battleData.baseOpponentAnima,
          false,
          0,
          true
        );

        return (battleData.randomBase, traitBattleData);
      } else {
        traitBattleData.attackerAnima = _calculateAnima(
          traitBattleData,
          battleData.attackerAddr,
          battleData.attackerId,
          battleData.baseAttackerAnima,
          false,
          0,
          traitBattleData.withinRange
        );

        traitBattleData.opponentAnima = 0;

        return (battleData.randomBase, traitBattleData);
      }
    }
  }

  function _calculateAnima(
    TraitBattleData memory data,
    address _winnerAddr,
    uint256 _winnerId,
    uint256 animaReward,
    bool hasBonus,
    uint256 _attackerReward,
    bool _withinRange
  ) internal returns (uint256) {
    // Check if bonus should be given
    uint256 animaBonus = hasBonus
      ? ((animaReward * _getAnimaMultiplier(MID - data.probability)) /
        PRECISION)
      : 0;

    // Add bonus to rewards
    uint256 anima = animaReward + animaBonus;

    // Check if out of range
    if (!_withinRange) {
      anima = anima / outOfRangeDivider;
    }

    emit ContenderRoll(
      fightId,
      _winnerAddr,
      _winnerId,
      data.traitId,
      hasBonus ? data.probability : UPPER - data.probability,
      anima,
      animaBonus,
      _attackerReward
    );

    return anima;
  }

  function _fight(
    uint256 _strongerTrait,
    uint256 _weakerTrait,
    uint256 _roll
  ) internal view returns (bool, bool, uint64) {
    // Add precision
    _strongerTrait = _strongerTrait * PRECISION;
    _weakerTrait = _weakerTrait * PRECISION;

    // Calculate min score
    uint256 minScore = (_strongerTrait / MIN_SCORE_RANGE);

    uint64 probability;

    // Check if weaker trait is too weak
    bool withinRange = _weakerTrait >= minScore;

    if (_weakerTrait < minScore) {
      probability = 0;
    } else {
      // Normalize
      probability = uint64(
        ((((_weakerTrait - minScore) * PRECISION) /
          ((_strongerTrait - minScore))) * MID) / PRECISION
      );
    }

    // Return true if fight was won by _weakerTrait
    if (uint64(_roll) <= probability) {
      return (true, withinRange, probability);
    }

    // Return false if fight was won by _strongerTrait
    return (false, withinRange, probability);
  }

  function _getAnima(
    address _addr,
    uint256 _adventurerId
  ) internal view returns (uint256) {
    uint256 level = ADVENTURER_DATA.aov(_addr, _adventurerId, 0);

    // Calculate anima based on transcendence level
    uint256 anima = level * animaBaseReward;

    return anima;
  }

  function _getAnimaMultiplier(uint256 _diff) internal view returns (uint256) {
    return (_diff * PRECISION * bonusMultiplier) / MAX_BONUS;
  }

  function _getParticleCost(
    address _addr,
    uint256 _adventurerId
  ) internal view returns (uint256) {
    // Calculate particle cost based on transcendence level
    return ADVENTURER_DATA.aov(_addr, _adventurerId, 0) * particleBaseCost;
  }
}

