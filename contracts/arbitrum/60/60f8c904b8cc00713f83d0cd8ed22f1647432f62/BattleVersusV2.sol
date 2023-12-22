// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

import "./IBattleVersusStorageV2.sol";
import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";
import "./IParticle.sol";
import "./IAnima.sol";
import "./IMissionOneStorage.sol";

import "./IRand.sol";

import "./ManagerModifier.sol";

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
  IMissionOneStorage public immutable MISSION_ONE_STORAGE;
  address public immutable VAULT;
  uint256 public immutable PRECISION;
  uint256 public immutable UPPER;
  uint256 public immutable MID;
  uint256 public immutable MAX_BONUS;
  uint256 public immutable XP_ID;
  uint256 public immutable MIN_SCORE_RANGE;
  uint256 public immutable BONUS_MULTIPLIER;

  //=======================================
  // Interface
  //=======================================
  IRand public randomizer;

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
    address _mission,
    address _vault,
    address _rand
  ) ManagerModifier(_manager) {
    STORAGE = IBattleVersusStorageV2(_storage);
    ADVENTURER_DATA = IAdventurerData(_data);
    GATEWAY = IAdventurerGateway(_gateway);
    PARTICLE = IParticle(_particle);
    ANIMA = IAnima(_anima);
    MISSION_ONE_STORAGE = IMissionOneStorage(_mission);
    VAULT = _vault;

    PRECISION = 10**9;
    UPPER = 98;
    MID = 49;
    MAX_BONUS = 49;
    XP_ID = 1;
    MIN_SCORE_RANGE = 2;
    BONUS_MULTIPLIER = 3;

    randomizer = IRand(_rand);

    animaBaseReward = 0.2 ether;
    animaPassiveRewardPercentage = 10;

    particleBaseCost = 0.025 ether;

    xpReward = 1;
    outOfRangeDivider = 10;
    attackerRewardDivider = 2;
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

      // Check attacker is eligible
      require(
        MISSION_ONE_STORAGE.isEligible(addr, adventurerId),
        "BattleVersusV2: Attacker is not eligible to battle"
      );

      // Check opponent is eligible
      require(
        MISSION_ONE_STORAGE.isEligible(oppAddr, oppAdventurerId),
        "BattleVersusV2: Opponent is not eligible to battle"
      );

      // Increment fight count
      fightId++;

      // Calculate particle cost
      uint256 particleCost = _getParticleCost(addr, adventurerId);

      // Transfer Particle to vault
      PARTICLE.safeTransferFrom(msg.sender, VAULT, particleCost);

      emit FightStarted(
        fightId,
        addr,
        adventurerId,
        oppAddr,
        oppAdventurerId,
        particleCost
      );

      // Begin battle
      _beginVersusBattle(addr, adventurerId, oppAddr, oppAdventurerId);

      // Set attacker epoch
      STORAGE.setAttackerEpoch(addr, adventurerId);
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

  function updateAnimaBaseRewards(uint256 _value) external onlyAdmin {
    animaBaseReward = _value;
  }

  function updateAnimaPassiveRewardPercentage(uint256 _value)
    external
    onlyAdmin
  {
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

  function updateRand(address _value) external onlyAdmin {
    randomizer = IRand(_value);
  }

  //=======================================
  // Internal
  //=======================================
  function _beginVersusBattle(
    address _attackerAddr,
    uint256 _attackerId,
    address _opponentAddr,
    uint256 _opponentId
  ) internal {
    uint256 contender1Wins;
    uint256 contender2Wins;

    // Calculate anima for contender 1
    uint256 animaForContender1 = _getAnima(_attackerAddr, _attackerId);

    // Calculate anima for contender 2
    uint256 animaForContender2 = (_getAnima(_opponentAddr, _opponentId) / 100) *
      animaPassiveRewardPercentage;

    for (uint256 traitId = 2; traitId < 8; traitId++) {
      uint256 attackerTrait = (ADVENTURER_DATA.base(
        _attackerAddr,
        _attackerId,
        traitId
      ) + 1);
      uint256 opponentTrait = (ADVENTURER_DATA.base(
        _opponentAddr,
        _opponentId,
        traitId
      ) + 1);

      bool contender1Won = _traitBattle(
        attackerTrait,
        opponentTrait,
        traitId,
        _attackerAddr,
        _attackerId,
        _opponentAddr,
        _opponentId,
        animaForContender1,
        animaForContender2
      );

      if (contender1Won) {
        contender1Wins++;
      } else {
        contender2Wins++;
      }
    }

    _results(
      _attackerAddr,
      _attackerId,
      _opponentAddr,
      _opponentId,
      contender1Wins,
      contender2Wins,
      animaForContender1,
      animaForContender2
    );
  }

  function _traitBattle(
    uint256 _attackerTrait,
    uint256 _opponentTrait,
    uint256 _traitId,
    address _attackerAddr,
    uint256 _attackerId,
    address _opponentAddr,
    uint256 _opponentId,
    uint256 _animaForContender1,
    uint256 _animaForContender2
  ) internal returns (bool) {
    if (_attackerTrait < _opponentTrait) {
      // Attacker is weaker
      (bool won, , uint256 probability) = _fight(
        _opponentTrait,
        _attackerTrait,
        _traitId
      );

      if (won) {
        _rewardWinner(
          won,
          _traitId,
          _attackerAddr,
          _attackerId,
          probability,
          _animaForContender1,
          true,
          0,
          true
        );

        return true;
      } else {
        // Calculate attacker rewards
        uint256 attackerReward = _animaForContender1 / attackerRewardDivider;

        // Attacker gets 50% rewards for taking the risk
        ANIMA.mintFor(
          ERC721(_attackerAddr).ownerOf(_attackerId),
          attackerReward
        );

        _rewardWinner(
          won,
          _traitId,
          _opponentAddr,
          _opponentId,
          probability,
          _animaForContender2,
          false,
          attackerReward,
          true
        );

        return false;
      }
    } else {
      // Opponent is weaker
      (bool won, bool withinRange, uint256 probability) = _fight(
        _attackerTrait,
        _opponentTrait,
        _traitId
      );

      if (won) {
        _rewardWinner(
          won,
          _traitId,
          _opponentAddr,
          _opponentId,
          probability,
          _animaForContender2,
          false,
          0,
          true
        );

        return false;
      } else {
        _rewardWinner(
          won,
          _traitId,
          _attackerAddr,
          _attackerId,
          probability,
          _animaForContender1,
          false,
          0,
          withinRange
        );

        return true;
      }
    }
  }

  function _rewardWinner(
    bool _won,
    uint256 _traitId,
    address _winnerAddr,
    uint256 _winnerId,
    uint256 _probability,
    uint256 animaReward,
    bool hasBonus,
    uint256 _attackerReward,
    bool _withinRange
  ) internal {
    uint256 animaBonus;

    // Check if bonus should be given
    if (hasBonus) {
      animaBonus = _getAnimaBonus(animaReward, MID - _probability);
    }

    // Add bonus to rewards
    uint256 anima = animaReward + animaBonus;

    // Check if out of range
    if (!_withinRange) {
      anima = anima / outOfRangeDivider;
    }

    // Mint Anima
    ANIMA.mintFor(ERC721(_winnerAddr).ownerOf(_winnerId), anima);

    emit ContenderRoll(
      fightId,
      _winnerAddr,
      _winnerId,
      _traitId,
      _won ? _probability : UPPER - _probability,
      anima,
      animaBonus,
      _attackerReward
    );
  }

  function _fight(
    uint256 _strongerTrait,
    uint256 _weakerTrait,
    uint256 _salt
  )
    internal
    view
    returns (
      bool,
      bool,
      uint256
    )
  {
    // Add precision
    _strongerTrait = _strongerTrait * PRECISION;
    _weakerTrait = _weakerTrait * PRECISION;

    // Calculate min score
    uint256 minScore = (_strongerTrait / MIN_SCORE_RANGE);

    uint256 probability;

    // Check if weaker trait is too weak
    bool withinRange = _weakerTrait >= minScore;

    if (_weakerTrait < minScore) {
      probability = 0;
    } else {
      // Normalize
      probability =
        (((_weakerTrait - minScore) * PRECISION) /
          ((_strongerTrait - minScore))) *
        MID;
    }

    // Remove precision
    probability = probability / PRECISION;

    // Return true if fight was won by _weakerTrait
    if (_getRand(_strongerTrait + _weakerTrait + _salt) <= probability) {
      return (true, withinRange, probability);
    }

    // Return false if fight was won by _strongerTrait
    return (false, withinRange, probability);
  }

  function _results(
    address _attackerAddr,
    uint256 _attackerId,
    address _opponentAddr,
    uint256 _opponentId,
    uint256 _contender1Wins,
    uint256 _contender2Wins,
    uint256 _anima1,
    uint256 _anima2
  ) internal {
    if (_contender1Wins > _contender2Wins) {
      // Mint Anima
      ANIMA.mintFor(ERC721(_attackerAddr).ownerOf(_attackerId), _anima1);

      emit OverallWinner(fightId, _attackerAddr, _attackerId, _anima1);
    } else {
      // Mint Anima
      ANIMA.mintFor(ERC721(_opponentAddr).ownerOf(_opponentId), _anima2);

      emit OverallWinner(fightId, _opponentAddr, _opponentId, _anima2);
    }

    // Add XP
    ADVENTURER_DATA.addToBase(_attackerAddr, _attackerId, XP_ID, xpReward);
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
    uint256 level = ADVENTURER_DATA.aov(_addr, _adventurerId, 0);

    // Calculate anima based on transcendence level
    uint256 anima = level * animaBaseReward;

    return anima;
  }

  function _getAnimaBonus(uint256 _anima, uint256 _diff)
    internal
    view
    returns (uint256)
  {
    uint256 normalized = (((_diff - 0) * PRECISION) / (MAX_BONUS - 0)) * 100;

    return (((_anima * BONUS_MULTIPLIER) / 100) * normalized) / PRECISION;
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

