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
import "./IBattleBoost.sol";

// Probabilities:
// Opponent too strong: 0 (lowest roll: 0 wins anyway)
// Opponent is stronger: 1-48 (2%-49% probability)
// Battle is even: 49 (50% probability)
// Attacker is stronger: 50-97 (51%-98% probability)
// Attacker too strong: 98 (highest roll: 99 loses anyway)

uint16 constant OPPONENT_TOO_STRONG_PROBABILITY = 0;
uint16 constant STRONGER_RANGE_OFFSET = 1;
// STRONGER_RANGE should really be 47 in floating point, but that's accounting for rounding errors when dealing with low range integers
uint256 constant STRONGER_RANGE = 48;
uint16 constant EVEN_BATTLE_PROBABILITY = 49;
uint16 constant REVERSE_PROBABILITY_UPPER_BOUND = 98;

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

  address public immutable AOV_ADDRESS;
  address public immutable VAULT;
  uint256 public immutable PRECISION;
  uint16 public immutable UPPER;
  uint256 public immutable MID;
  uint256 public immutable LEVEL_ID;
  uint256 public immutable XP_ID;
  uint256 public immutable MIN_SCORE_RANGE;

  //=======================================
  // Interfaces
  //=======================================
  IBattleBoost public battleBoost;

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
  uint256 public animaDivider;

  //=======================================
  // Per trait Rewards Config
  //=======================================
  LootBoxRewardRarityConfig public lootBoxRewardRarityConfig;
  mapping(uint16 => Rewards) public probabilityPerTraitRewardsMap;

  //=======================================
  // XP Rewards
  //=======================================
  uint16[7] public xpRewards;

  //=======================================
  // Structs
  //=======================================
  struct Rewards {
    uint256 attackerWinAnimaBase;
    uint256 attackerLossAnimaBase;
    uint256 opponentWinAnimaBase;
    uint256 opponentLossAnimaBase;
    uint32 lootBoxChance;
    uint16 traitUpgradeThreshold;
    uint32 traitUpgradePoints;
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
    uint256 attackerLevel;
    uint256 lpAnimaBonus;
    address opponentOwner;
  }

  struct BattleData {
    address attackerAddr;
    uint256 attackerId;
    address opponentAddr;
    uint256 opponentId;
    uint256 attackerLevel;
    uint256 opponentLevel;
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
    uint16 roll;
    uint64 lootBoxChance;
    uint16 probability;
    bool won;
    uint16 traitUpgrade;
  }

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
    address loserAddr,
    uint256 loserId,
    uint256 traitId,
    uint256 probability,
    uint256 roll,
    uint256 winnerAnima,
    uint256 loserAnima,
    uint256 traitUpgrade
  );

  event OverallWinner(
    uint256 fightId,
    address winnerAddr,
    uint256 winnerId,
    address loserAddr,
    uint256 loserId,
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
    address _vault,
    address _aov
  ) ManagerModifier(_manager) {
    STORAGE = IBattleVersusStorageV2(_storage);
    ADVENTURER_DATA = IAdventurerData(_data);
    GATEWAY = IAdventurerGateway(_gateway);
    ANIMA = IAnima(_anima);
    BATTLE_ENTRY = IBattleEntry(_battleEntry);
    VAULT = _vault;
    LOOTBOX_DISPENSER = ILootBoxDispenser(_lootBoxDispenser);

    AOV_ADDRESS = _aov;

    PRECISION = 10 ** 9;
    UPPER = 98;
    MID = 49;
    LEVEL_ID = 0;
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
    animaDivider = 5;
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
    require(
      msg.sender == tx.origin,
      "Battling is not allowed through another contract"
    );

    FightData memory fightData;
    fightData.randomBase = Random.startRandomBase(
      uint256(uint160(msg.sender)),
      fightId
    );

    uint256 playerBaseLpBonus;
    if (address(battleBoost) != address(0)) {
      playerBaseLpBonus = battleBoost.getAnimaBase(msg.sender);
    }

    for (uint256 j = 0; j < _adventurerIds.length; j++) {
      address addr = _addresses[j];
      uint256 adventurerId = _adventurerIds[j];
      address oppAddr = _oppAddresses[j];
      uint256 oppAdventurerId = _oppAdventurerIds[j];

      // Calculate lp anima bonus
      fightData.attackerLevel = ADVENTURER_DATA.aov(addr, adventurerId, 0);
      fightData.lpAnimaBonus = playerBaseLpBonus * fightData.attackerLevel;

      emit FightStarted(
        fightId,
        addr,
        adventurerId,
        oppAddr,
        oppAdventurerId,
        fightData.lpAnimaBonus
      );

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

      fightData.opponentOwner = ERC721(oppAddr).ownerOf(oppAdventurerId);

      // Verify sender is not self-battling
      require(
        fightData.opponentOwner != msg.sender,
        "BattleVersusV2: Self-battles are not allowed"
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

      // Begin battle
      (
        fightData.attackerReward,
        fightData.opponentReward,
        fightData.randomBase
      ) = _beginVersusBattle(
        addr,
        adventurerId,
        fightData.attackerLevel,
        oppAddr,
        oppAdventurerId,
        fightData.randomBase
      );

      uint256 totalAnimaRewards = fightData.attackerReward +
        fightData.lpAnimaBonus;

      // Add attacker rewards to total anima
      fightData.totalAnima += totalAnimaRewards;

      // Mint anima rewards for opponent
      if (fightData.opponentReward > 0) {
        _mintAnimaForOpponent(
          fightData.opponentOwner,
          fightData.opponentReward
        );
      }

      // Set attacker epoch
      STORAGE.setAttackerEpoch(addr, adventurerId);

      // Increment fight count
      fightId++;
    }

    // Mint attacker anima rewards
    if (fightData.totalAnima > 0) {
      ANIMA.mintFor(msg.sender, fightData.totalAnima);
    }
  }

  function lpAnimaBase(address addr) external view returns (uint256) {
    if (address(battleBoost) == address(0)) {
      return 0;
    }
    return battleBoost.getAnimaBase(addr);
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

  function updateOutOfRangeDivider(uint256 _value) external onlyAdmin {
    outOfRangeDivider = _value;
  }

  function updateAttackerRewardDivider(uint256 _value) external onlyAdmin {
    attackerRewardDivider = _value;
  }

  function updateLpBattleBoost(address _battleBoost) external onlyAdmin {
    battleBoost = IBattleBoost(_battleBoost);
  }

  function updatePerTraitRewardsMap(
    Rewards[] calldata rewards
  ) external onlyAdmin {
    require(rewards.length == 100);
    for (uint16 i = 0; i < 100; i++) {
      probabilityPerTraitRewardsMap[i] = rewards[i];
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

  function updateAnimaDivider(uint256 _value) external onlyAdmin {
    animaDivider = _value;
  }

  //=======================================
  // Internal
  //=======================================

  function _beginVersusBattle(
    address _attackerAddr,
    uint256 _attackerId,
    uint256 _attackerLevel,
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

    battleData.attackerLevel = _attackerLevel;
    battleData.opponentLevel = ADVENTURER_DATA.aov(
      _opponentAddr,
      _opponentId,
      0
    );

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

      battleData.lootBoxChance += traitBattleData.lootBoxChance;

      // Add attacker rewards
      battleData.attackerReward += traitBattleData.attackerAnima;

      // Add opponent rewards
      battleData.opponentReward += traitBattleData.opponentAnima;

      // Add to wins
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

    // Get XP rewards
    battleData.xpReward = xpRewards[battleData.wins];

    // Check if XP rewards is greater than zero
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
        _opponentAddr,
        _opponentId,
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
        _attackerAddr,
        _attackerId,
        battleData.opponentReward,
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
    uint256 bigRoll;
    (bigRoll, battleData.randomBase) = Random.getNextRandom(
      battleData.randomBase,
      100
    );

    traitBattleData.roll = uint16(bigRoll);
    traitBattleData.probability = _calculateTraitProbability(
      traitBattleData.attackerTrait,
      traitBattleData.opponentTrait
    );
    traitBattleData.won = traitBattleData.roll <= traitBattleData.probability;

    Rewards storage rewards = probabilityPerTraitRewardsMap[
      traitBattleData.probability
    ];

    if (traitBattleData.roll < rewards.traitUpgradeThreshold) {
      (bigRoll, battleData.randomBase) = Random.getNextRandom(
        battleData.randomBase,
        ONE_HUNDRED
      );

      // Upgrade as many points as needed:
      // For each full 100000 we upgrade trait by 1
      // The remaining 0-100000 is a roll to upgrade
      traitBattleData.traitUpgrade = (uint16)(
        rewards.traitUpgradePoints / ONE_HUNDRED
      );

      if (uint32(bigRoll) < (rewards.traitUpgradePoints % ONE_HUNDRED)) {
        traitBattleData.traitUpgrade += 1;
      }

      if (traitBattleData.traitUpgrade > 0) {
        ADVENTURER_DATA.addToBase(
          battleData.attackerAddr,
          battleData.attackerId,
          traitBattleData.traitId,
          traitBattleData.traitUpgrade
        );
      }
    } else {
      traitBattleData.traitUpgrade = 0;
    }

    if (traitBattleData.won) {
      traitBattleData.attackerAnima =
        battleData.attackerLevel *
        rewards.attackerWinAnimaBase;

      traitBattleData.opponentAnima =
        battleData.opponentLevel *
        rewards.opponentLossAnimaBase;

      // Check if not AoV
      if (battleData.attackerAddr != AOV_ADDRESS) {
        traitBattleData.attackerAnima =
          traitBattleData.attackerAnima /
          animaDivider;

        traitBattleData.opponentAnima =
          traitBattleData.opponentAnima /
          animaDivider;
      } else if (battleData.opponentAddr != AOV_ADDRESS) {
        traitBattleData.opponentAnima =
          traitBattleData.opponentAnima /
          animaDivider;
      }

      emit ContenderRoll(
        fightId,
        battleData.attackerAddr,
        battleData.attackerId,
        battleData.opponentAddr,
        battleData.opponentId,
        traitBattleData.traitId,
        traitBattleData.probability,
        traitBattleData.roll,
        traitBattleData.attackerAnima,
        traitBattleData.opponentAnima,
        traitBattleData.traitUpgrade
      );
    } else {
      traitBattleData.attackerAnima =
        battleData.attackerLevel *
        rewards.attackerLossAnimaBase;

      traitBattleData.opponentAnima =
        battleData.opponentLevel *
        rewards.opponentWinAnimaBase;

      // Check if not AoV
      if (battleData.attackerAddr != AOV_ADDRESS) {
        traitBattleData.attackerAnima =
          traitBattleData.attackerAnima /
          animaDivider;

        traitBattleData.opponentAnima =
          traitBattleData.opponentAnima /
          animaDivider;
      } else if (battleData.opponentAddr != AOV_ADDRESS) {
        traitBattleData.opponentAnima =
          traitBattleData.opponentAnima /
          animaDivider;
      }

      emit ContenderRoll(
        fightId,
        battleData.opponentAddr,
        battleData.opponentId,
        battleData.attackerAddr,
        battleData.attackerId,
        traitBattleData.traitId,
        traitBattleData.probability,
        traitBattleData.roll,
        traitBattleData.opponentAnima,
        traitBattleData.attackerAnima,
        traitBattleData.traitUpgrade
      );
    }

    traitBattleData.lootBoxChance = rewards.lootBoxChance;

    return (battleData.randomBase, traitBattleData);
  }

  function _calculateTraitProbability(
    uint256 attackerTrait,
    uint256 opponentTrait
  ) internal view returns (uint16) {
    if (attackerTrait == opponentTrait) {
      return EVEN_BATTLE_PROBABILITY;
    }

    if (attackerTrait < opponentTrait) {
      // Attacker is weaker
      return _getProbability(opponentTrait, attackerTrait);
    } else {
      // Attacker is stronger
      return
        REVERSE_PROBABILITY_UPPER_BOUND -
        _getProbability(attackerTrait, opponentTrait);
    }
  }

  function _getProbability(
    uint256 strongerTrait,
    uint256 weakerTrait
  ) internal view returns (uint16 probability) {
    strongerTrait = strongerTrait * PRECISION;
    weakerTrait = weakerTrait * PRECISION;
    // Calculate min score
    uint256 minScore = (strongerTrait / MIN_SCORE_RANGE);

    // Check if weaker trait is too weak
    if (weakerTrait < minScore) {
      probability = OPPONENT_TOO_STRONG_PROBABILITY;
    } else {
      // Normalize
      probability =
        STRONGER_RANGE_OFFSET +
        uint16(
          ((STRONGER_RANGE * (weakerTrait - minScore)) /
            (strongerTrait - minScore))
        );
    }

    return probability;
  }

  function _mintAnimaForOpponent(
    address _receiverAddr,
    uint256 _amount
  ) internal {
    ANIMA.mintFor(_receiverAddr, _amount);
  }
}

