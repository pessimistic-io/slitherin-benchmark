// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./ERC721.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

import "./IBattleVersusStorageV2.sol";
import "./IAdventurerData.sol";
import "./IAdventurerGateway.sol";
import "./IAnima.sol";
import "./IBattleEntry.sol";

import "./ManagerModifier.sol";
import "./Random.sol";
import "./ILootBoxDispenser.sol";

contract BattleVersusV2 is ReentrancyGuard, Pausable, ManagerModifier {
  using SafeERC20 for IAnima;

  //=======================================
  // Immutables
  //=======================================
  IBattleVersusStorageV2 public immutable STORAGE;
  IAdventurerData public immutable ADVENTURER_DATA;
  IAdventurerGateway public immutable GATEWAY;
  IAnima public immutable ANIMA;
  IBattleEntry public immutable BATTLE_ENTRY;
  ILootBoxDispenser public immutable LOOTBOX_DISPENSER;
  address public immutable VAULT;
  uint256 public immutable PRECISION;
  uint16 public immutable UPPER;
  uint256 public immutable MID;
  uint256 public immutable XP_ID;
  uint256 public immutable MIN_SCORE_RANGE;

  //=======================================
  // Constants
  //=======================================
  uint256 constant DECIMAL_POINT = 1000;
  uint256 constant ONE_HUNDRED = 100 * DECIMAL_POINT;

  //=======================================
  // Uints
  //=======================================
  uint256 public fightId;
  uint256 public animaBaseReward;
  uint256 public animaPassiveRewardPercentage;
  uint256 public outOfRangeDivider;
  uint256 public attackerRewardDivider;

  //=======================================
  // LP Rewards Config
  //=======================================

  ERC20 public lpToken;
  uint256[] public lpBonusThresholds;
  uint256 public lpAnimaRewardPerTier;

  //=======================================
  // LootBox Rewards Config
  //=======================================
  LootBoxRewardRarityConfig public lootBoxRewardRarityConfig;
  mapping(uint16 => uint32) public perTraitLootBoxProbabilityMap;

  //=======================================
  // Anima rewards
  //=======================================

  uint256[3] public animaRewardsProbabilityThresholds;
  uint256[3] public animaRewardsMultipliers;

  //=======================================
  // XP Rewards
  //=======================================
  uint16[7] public xpRewards;

  //=======================================
  // Events
  //=======================================
  event FightStarted(
    uint256 fightId,
    address attackerAddr,
    uint256 attackerId,
    address opponentAddr,
    uint256 opponentId,
    uint256 lpAnimaBonus
  );
  event ContenderRoll(
    uint256 fightId,
    address winnerAddr,
    uint256 winnerId,
    uint256 traitId,
    uint256 probability,
    uint256 animaReward,
    uint256 attackerReward
  );
  event OverallWinner(
    uint256 fightId,
    address addr,
    uint256 adventureId,
    uint256 anima,
    uint256 attackerLootBoxTokenId,
    uint256 attackerXpReward,
    uint256 wins
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _storage,
    address _data,
    address _gateway,
    address _anima,
    address _battleEntry,
    address _lootBoxDispenser,
    address _vault
  ) ManagerModifier(_manager) {
    STORAGE = IBattleVersusStorageV2(_storage);
    ADVENTURER_DATA = IAdventurerData(_data);
    GATEWAY = IAdventurerGateway(_gateway);
    ANIMA = IAnima(_anima);
    BATTLE_ENTRY = IBattleEntry(_battleEntry);
    VAULT = _vault;
    LOOTBOX_DISPENSER = ILootBoxDispenser(_lootBoxDispenser);

    PRECISION = 10 ** 9;
    UPPER = 98;
    MID = 49;
    XP_ID = 1;
    MIN_SCORE_RANGE = 2;

    animaBaseReward = 0.1 ether;
    animaPassiveRewardPercentage = 10;

    xpRewards[0] = 0;
    xpRewards[1] = 0;
    xpRewards[2] = 0;
    xpRewards[3] = 0;
    xpRewards[4] = 1;
    xpRewards[5] = 1;
    xpRewards[6] = 2;

    outOfRangeDivider = 10;
    attackerRewardDivider = 0;

    lpAnimaRewardPerTier = 0.05 ether;

    animaRewardsProbabilityThresholds[0] = 4;
    animaRewardsProbabilityThresholds[1] = 49;
    animaRewardsProbabilityThresholds[2] = 74;

    animaRewardsMultipliers[0] = 24;
    animaRewardsMultipliers[1] = 6;
    animaRewardsMultipliers[2] = 2;
  }

  struct LootBoxRewardRarityConfig {
    uint256 lootBoxTotalChance;
    uint256[] lootBoxChances;
    uint256[] lootBoxTokenIds;
    uint256[] lootBoxMinimumLevels;
  }

  struct FightData {
    uint256 totalAnima;
    uint256 attackerReward;
    uint256 opponentReward;
    uint256 randomBase;
    uint256 lpAnimaBonus;
  }

  //=======================================
  // External
  //=======================================

  function lpBonusMultiplier(address addr) external view returns (uint256) {
    return _getLpBonusMultiplier(addr);
  }

  function fight(
    address[] calldata _addresses,
    uint256[] calldata _adventurerIds,
    bytes32[][] memory _proofs,
    address[] calldata _oppAddresses,
    uint256[] calldata _oppAdventurerIds,
    bytes32[][] memory _oppProofs
  ) external nonReentrant whenNotPaused {
    require(
      msg.sender == tx.origin,
      "Battling is not allowed through another contract"
    );

    FightData memory fightData;
    fightData.lpAnimaBonus =
      _getLpBonusMultiplier(msg.sender) *
      lpAnimaRewardPerTier;
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
      BattleEntryEligibility eligibility = BATTLE_ENTRY.isEligible(
        oppAddr,
        oppAdventurerId
      );
      if (eligibility == BattleEntryEligibility.UNINITIALIZED) {
        BATTLE_ENTRY.set(oppAddr, oppAdventurerId);
        eligibility = BattleEntryEligibility.ELIGIBLE;
      }
      require(
        eligibility == BattleEntryEligibility.ELIGIBLE,
        "BattleVersusV2: Opponent is not eligible"
      );

      // Set entry
      BATTLE_ENTRY.set(addr, adventurerId);

      // Increment fight count
      fightId++;

      emit FightStarted(
        fightId,
        addr,
        adventurerId,
        oppAddr,
        oppAdventurerId,
        fightData.lpAnimaBonus
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
      fightData.totalAnima += fightData.attackerReward + fightData.lpAnimaBonus;

      // Mint anima rewards for opponent
      if (fightData.opponentReward > 0) {
        ANIMA.mintFor(
          ERC721(oppAddr).ownerOf(oppAdventurerId),
          fightData.opponentReward
        );
      }

      // Set attacker epoch
      STORAGE.setAttackerEpoch(addr, adventurerId);
    }

    // Mint attacker anima rewards
    ANIMA.mintFor(msg.sender, fightData.totalAnima);
  }

  function _getLpBonusMultiplier(
    address addr
  ) internal view returns (uint256 multiplier) {
    if (address(lpToken) == address(0)) {
      return multiplier;
    }

    uint256 totalSupply = lpToken.totalSupply();
    if (totalSupply == 0) {
      return multiplier;
    }

    uint256 balancePercentage = (lpToken.balanceOf(addr) * ONE_HUNDRED) /
      totalSupply;
    for (uint256 i = 0; i < lpBonusThresholds.length; i++) {
      if (balancePercentage > lpBonusThresholds[i]) {
        multiplier++;
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

  function updateAnimaBaseRewards(uint256 _value) external onlyAdmin {
    animaBaseReward = _value;
  }

  function updateAnimaPassiveRewardPercentage(
    uint256 _value
  ) external onlyAdmin {
    animaPassiveRewardPercentage = _value;
  }

  function updateXpReward(uint16[7] calldata _xpRewards) external onlyAdmin {
    xpRewards = _xpRewards;
  }

  function updateAnimaRewards(
    uint256[3] calldata _thresholds,
    uint256[3] calldata _multipliers
  ) external onlyAdmin {
    require(_thresholds.length == _multipliers.length, "Invalid array sizes");
    animaRewardsProbabilityThresholds = _thresholds;
    animaRewardsMultipliers = _multipliers;
  }

  function updateOutOfRangeDivider(uint256 _value) external onlyAdmin {
    outOfRangeDivider = _value;
  }

  function updateAttackerRewardDivider(uint256 _value) external onlyAdmin {
    attackerRewardDivider = _value;
  }

  function updateLpToken(address _lpToken) external onlyAdmin {
    lpToken = ERC20(_lpToken);
  }

  function updateLpBonusThresholds(
    uint256[] calldata _lpBonusThresholds
  ) external onlyAdmin {
    lpBonusThresholds = _lpBonusThresholds;
  }

  function updateLpAnimaBonusPerThreshold(uint256 _anima) external onlyAdmin {
    lpAnimaRewardPerTier = _anima;
  }

  function updateLootBoxPerTraitProbabilityMap(
    uint16[] calldata probabilities
  ) external onlyAdmin {
    require(probabilities.length == 100);
    for (uint16 i = 0; i < 100; i++) {
      perTraitLootBoxProbabilityMap[i] = probabilities[i];
    }
  }

  function updateLootboxRarityConfig(
    uint256[] calldata _chances,
    uint256[] calldata _minimumLevels,
    uint256[] calldata _tokenIds
  ) external onlyAdmin {
    uint256 totalChance;

    for (uint256 i = 0; i < _chances.length; i++) {
      totalChance += _chances[i];
    }

    lootBoxRewardRarityConfig = LootBoxRewardRarityConfig(
      totalChance,
      _chances,
      _tokenIds,
      _minimumLevels
    );
  }

  //=======================================
  // Internal
  //=======================================

  struct BattleData {
    address attackerAddr;
    uint256 attackerId;
    address opponentAddr;
    uint256 opponentId;
    uint256 attackerLevel;
    uint256 baseAttackerAnima;
    uint256 baseOpponentAnima;
    uint256 attackerReward;
    uint256 opponentReward;
    uint256 randomBase;
    uint256 lootBoxChance;
    uint16 wins;
    uint16 xpReward;
  }

  struct TraitBattleData {
    uint256 traitId;
    uint256 attackerTrait;
    uint256 opponentTrait;
    uint256 attackerAnima;
    uint256 opponentAnima;
    uint256 roll;
    uint64 lootBoxChance;
    uint16 probability;
    bool won;
    bool withinRange;
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
    (battleData.baseAttackerAnima, battleData.attackerLevel) = _getAnima(
      _attackerAddr,
      _attackerId
    );

    // Calculate anima for contender 2
    (battleData.baseOpponentAnima, ) = _getAnima(_opponentAddr, _opponentId);
    battleData.baseOpponentAnima =
      (battleData.baseOpponentAnima / 100) *
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

      battleData.lootBoxChance += (uint256)(
        perTraitLootBoxProbabilityMap[traitBattleData.probability]
      );

      // Add attacker anima rewards
      battleData.attackerReward += traitBattleData.attackerAnima;

      // Add anima rewards
      battleData.opponentReward += traitBattleData.opponentAnima;
      if (traitBattleData.won) {
        battleData.wins++;
      }
    }

    // Init LootBox ID
    uint256 lootBoxId;

    // Try dispensing a LootBox
    (lootBoxId, battleData.randomBase) = _tryDispenseLootBox(
      battleData.lootBoxChance,
      battleData.randomBase,
      battleData.attackerLevel
    );

    battleData.xpReward = xpRewards[battleData.wins];
    if (battleData.xpReward > 0) {
      ADVENTURER_DATA.addToBase(
        _attackerAddr,
        _attackerId,
        XP_ID,
        battleData.xpReward
      );
    }

    if (battleData.wins > 3) {
      emit OverallWinner(
        fightId,
        _attackerAddr,
        _attackerId,
        battleData.attackerReward,
        lootBoxId,
        battleData.xpReward,
        battleData.wins
      );
    } else {
      emit OverallWinner(
        fightId,
        _opponentAddr,
        _opponentId,
        battleData.attackerReward,
        lootBoxId,
        battleData.xpReward,
        battleData.wins
      );
    }

    return (
      battleData.attackerReward,
      battleData.opponentReward,
      battleData.randomBase
    );
  }

  function _tryDispenseLootBox(
    uint256 _probability,
    uint256 _randomBase,
    uint256 _attackerLevel
  ) internal returns (uint256 tokenId, uint256 randomBase) {
    uint256 roll;
    // Get roll and random base
    (roll, randomBase) = Random.getNextRandom(_randomBase, ONE_HUNDRED);
    if (roll > _probability) {
      return (tokenId, randomBase);
    }

    (roll, randomBase) = Random.getNextRandom(
      randomBase,
      lootBoxRewardRarityConfig.lootBoxTotalChance
    );

    // Check if roll is less than total chance and is overal winner
    // Also checks if configuration is set to always dispense lootbox
    for (
      uint256 i = 0;
      i < lootBoxRewardRarityConfig.lootBoxChances.length;
      i++
    ) {
      if (roll >= lootBoxRewardRarityConfig.lootBoxChances[i]) {
        roll -= lootBoxRewardRarityConfig.lootBoxChances[i];
        continue;
      }

      if (_attackerLevel < lootBoxRewardRarityConfig.lootBoxMinimumLevels[i]) {
        roll = 0;
        continue;
      }

      // Assign token
      tokenId = lootBoxRewardRarityConfig.lootBoxTokenIds[i];

      // Dispense LootBox
      LOOTBOX_DISPENSER.dispense(msg.sender, tokenId, 1);

      break;
    }
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
          battleData.attackerAddr,
          battleData.attackerId,
          battleData.baseAttackerAnima,
          0,
          true,
          traitBattleData.probability,
          traitBattleData.traitId
        );

        traitBattleData.opponentAnima = 0;

        return (battleData.randomBase, traitBattleData);
      } else {
        // Calculate attacker rewards
        // Attacker gets 50% rewards for taking the risk
        if (attackerRewardDivider > 0) {
          traitBattleData.attackerAnima =
            battleData.baseAttackerAnima /
            attackerRewardDivider;
        } else {
          traitBattleData.attackerAnima = 0;
        }

        traitBattleData.opponentAnima = _calculateAnima(
          battleData.opponentAddr,
          battleData.opponentId,
          battleData.baseOpponentAnima,
          traitBattleData.attackerAnima,
          true,
          99 - traitBattleData.probability,
          traitBattleData.traitId
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

      traitBattleData.probability = UPPER - traitBattleData.probability;
      traitBattleData.won = !traitBattleData.won;
      traitBattleData.roll = 99 - traitBattleData.roll;

      if (traitBattleData.won) {
        traitBattleData.attackerAnima = _calculateAnima(
          battleData.attackerAddr,
          battleData.attackerId,
          battleData.baseAttackerAnima,
          0,
          traitBattleData.withinRange,
          traitBattleData.probability,
          traitBattleData.traitId
        );

        traitBattleData.opponentAnima = 0;

        return (battleData.randomBase, traitBattleData);
      } else {
        traitBattleData.attackerAnima = 0;

        traitBattleData.opponentAnima = _calculateAnima(
          battleData.opponentAddr,
          battleData.opponentId,
          battleData.baseOpponentAnima,
          0,
          true,
          99 - traitBattleData.probability,
          traitBattleData.traitId
        );
        return (battleData.randomBase, traitBattleData);
      }
    }
  }

  function _calculateAnima(
    address _winnerAddr,
    uint256 _winnerId,
    uint256 _animaReward,
    uint256 _attackerReward,
    bool _withinRange,
    uint256 probability,
    uint256 traitId
  ) internal returns (uint256) {
    // Add bonus to rewards
    uint256 multiplier = _getAnimaMultiplier(probability);
    uint256 anima = _animaReward * multiplier;

    // Check if out of range
    if (!_withinRange) {
      anima = anima / outOfRangeDivider;
    }

    emit ContenderRoll(
      fightId,
      _winnerAddr,
      _winnerId,
      traitId,
      probability,
      anima,
      _attackerReward
    );

    return anima;
  }

  function _fight(
    uint256 _strongerTrait,
    uint256 _weakerTrait,
    uint256 _roll
  ) internal view returns (bool, bool, uint16) {
    // Add precision
    _strongerTrait = _strongerTrait * PRECISION;
    _weakerTrait = _weakerTrait * PRECISION;

    // Calculate min score
    uint256 minScore = (_strongerTrait / MIN_SCORE_RANGE);

    uint16 probability;

    // Check if weaker trait is too weak
    bool withinRange = _weakerTrait >= minScore;

    if (_weakerTrait < minScore) {
      probability = 0;
    } else {
      // Normalize
      probability = uint16(
        ((((_weakerTrait - minScore) * PRECISION) /
          ((_strongerTrait - minScore))) * MID) / PRECISION
      );
    }

    // Return true if fight was won by _weakerTrait
    if (uint16(_roll) <= probability) {
      return (true, withinRange, probability);
    }

    // Return false if fight was won by _strongerTrait
    return (false, withinRange, probability);
  }

  function _getAnima(
    address _addr,
    uint256 _adventurerId
  ) internal view returns (uint256 anima, uint256 level) {
    level = ADVENTURER_DATA.aov(_addr, _adventurerId, 0);

    // Calculate anima based on transcendence level
    anima = level * animaBaseReward;
  }

  function _getAnimaMultiplier(
    uint256 _probability
  ) internal view returns (uint256) {
    for (uint i = 0; i < animaRewardsProbabilityThresholds.length; i++) {
      if (_probability < animaRewardsProbabilityThresholds[i]) {
        return animaRewardsMultipliers[i];
      }
    }
    return 1;
  }
}

