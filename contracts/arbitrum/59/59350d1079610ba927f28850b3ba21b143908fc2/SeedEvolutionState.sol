//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./IRandomizer.sol";
import "./ISeedEvolution.sol";
import "./ISeedOfLife.sol";
import "./IMagic.sol";
import "./IBalancerCrystal.sol";
import "./IImbuedSoul.sol";
import "./AdminableUpgradeable.sol";
import "./ITreasureMetadataStore.sol";
import "./ITreasure.sol";
import "./ISoLItem.sol";

abstract contract SeedEvolutionState is Initializable, ISeedEvolution, ERC1155HolderUpgradeable, AdminableUpgradeable {

    event LifeformCreated(uint256 indexed _lifeformId, LifeformInfo _evolutionInfo);

    event StartedUnstakingTreasure(uint256 _lifeformId, uint256 _requestId);
    event FinishedUnstakingTreasure(address _owner, uint256[] _brokenTreasureIds, uint256[] _brokenTreasureAmounts);

    event StartedClaimingImbuedSoul(uint256 _lifeformId, uint256 _claimRequestId);
    event ImbuedSoulClaimed(address _owner, uint256 _lifeformId);

    IRandomizer public randomizer;
    ISeedOfLife public seedOfLife;
    IBalancerCrystal public balancerCrystal;
    IMagic public magic;
    IImbuedSoul public imbuedSoul;
    ITreasureMetadataStore public treasureMetadataStore;
    ITreasure public treasure;
    ISoLItem public solItem;

    address public treasuryAddress;

    uint256 public balancerCrystalId;
    uint256 public magicCost;
    uint256 public balancerCrystalStakeAmount;
    uint256 public seedOfLife1Id;
    uint256 public seedOfLife2Id;

    uint256 public timeUntilOffensiveSkill;
    uint256 public timeUntilFirstSecondarySkill;
    uint256 public timeUntilSecondSecondarySkill;
    // Not used!
    uint256 public timeUntilLandDeed;
    uint256 public timeUntilDeath;

    LifeformClass[] public availableClasses;
    mapping(LifeformClass => uint256) public classToOdds;

    mapping(LifeformClass => OffensiveSkill) public classToOffensiveSkill;

    mapping(LifeformRealm => SecondarySkill[]) public realmToSecondarySkills;
    mapping(SecondarySkill => uint256) public secondarySkillToOdds;

    uint256 public lifeformIdCur;

    mapping(address => EnumerableSetUpgradeable.UintSet) internal userToLifeformIds;
    mapping(uint256 => LifeformInfo) public lifeformIdToInfo;

    mapping(uint8 => uint256) public treasureTierToBoost;

    uint256 public staminaPotionId;
    uint256 public staminaPotionRewardAmount;
    mapping(Path => uint256) public pathToBasePotionPercent;

    mapping(address => UnstakingTreasure) userToUnstakingTreasure;

    uint256 public treasureBreakOdds;

    string public baseTokenUri;

    uint256 public timeBCAndTreasureStakingShutdown;

    function __SeedEvolutionState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        balancerCrystalId = 1;
        lifeformIdCur = 1;
        magicCost = 50 ether;
        balancerCrystalStakeAmount = 1;
        seedOfLife1Id = 142;
        seedOfLife2Id = 143;

        timeUntilOffensiveSkill = 3 weeks;
        timeUntilFirstSecondarySkill = 4 weeks;
        timeUntilSecondSecondarySkill = 6 weeks;
        timeUntilDeath = 8 weeks;

        availableClasses.push(LifeformClass.WARRIOR);
        availableClasses.push(LifeformClass.MAGE);
        availableClasses.push(LifeformClass.PRIEST);
        availableClasses.push(LifeformClass.SHARPSHOOTER);
        availableClasses.push(LifeformClass.SUMMONER);
        availableClasses.push(LifeformClass.PALADIN);
        availableClasses.push(LifeformClass.ASURA);
        availableClasses.push(LifeformClass.SLAYER);

        classToOdds[LifeformClass.WARRIOR] = 30000;
        classToOdds[LifeformClass.MAGE] = 30000;
        classToOdds[LifeformClass.PRIEST] = 12500;
        classToOdds[LifeformClass.SHARPSHOOTER] = 12500;
        classToOdds[LifeformClass.SUMMONER] = 5000;
        classToOdds[LifeformClass.PALADIN] = 5000;
        classToOdds[LifeformClass.ASURA] = 2500;
        classToOdds[LifeformClass.SLAYER] = 2500;

        classToOffensiveSkill[LifeformClass.WARRIOR] = OffensiveSkill.BERSERKER;
        classToOffensiveSkill[LifeformClass.MAGE] = OffensiveSkill.METEOR_SWARM;
        classToOffensiveSkill[LifeformClass.PRIEST] = OffensiveSkill.HOLY_ARROW;
        classToOffensiveSkill[LifeformClass.SHARPSHOOTER] = OffensiveSkill.MULTISHOT;
        classToOffensiveSkill[LifeformClass.SUMMONER] = OffensiveSkill.SUMMON_MINION;
        classToOffensiveSkill[LifeformClass.PALADIN] = OffensiveSkill.THORS_HAMMER;
        classToOffensiveSkill[LifeformClass.ASURA] = OffensiveSkill.MINDBURN;
        classToOffensiveSkill[LifeformClass.SLAYER] = OffensiveSkill.BACKSTAB;

		realmToSecondarySkills[LifeformRealm.VESPER].push(SecondarySkill.POTION_OF_SWIFTNESS);
		realmToSecondarySkills[LifeformRealm.VESPER].push(SecondarySkill.POTION_OF_RECOVERY);
		realmToSecondarySkills[LifeformRealm.VESPER].push(SecondarySkill.POTION_OF_GLUTTONY);
		realmToSecondarySkills[LifeformRealm.SHERWOOD].push(SecondarySkill.BEGINNER_GARDENING_KIT);
		realmToSecondarySkills[LifeformRealm.SHERWOOD].push(SecondarySkill.INTERMEDIATE_GARDENING_KIT);
		realmToSecondarySkills[LifeformRealm.SHERWOOD].push(SecondarySkill.EXPERT_GARDENING_KIT);
		realmToSecondarySkills[LifeformRealm.THOUSAND_ISLES].push(SecondarySkill.SHADOW_WALK);
		realmToSecondarySkills[LifeformRealm.THOUSAND_ISLES].push(SecondarySkill.SHADOW_ASSAULT);
		realmToSecondarySkills[LifeformRealm.THOUSAND_ISLES].push(SecondarySkill.SHADOW_OVERLORD);
		realmToSecondarySkills[LifeformRealm.TUL_NIELOHG_DESERT].push(SecondarySkill.SPEAR_OF_FIRE);
		realmToSecondarySkills[LifeformRealm.TUL_NIELOHG_DESERT].push(SecondarySkill.SPEAR_OF_FLAME);
		realmToSecondarySkills[LifeformRealm.TUL_NIELOHG_DESERT].push(SecondarySkill.SPEAR_OF_INFERNO);
		realmToSecondarySkills[LifeformRealm.DULKHAN_MOUNTAINS].push(SecondarySkill.SUMMON_BROWN_BEAR);
		realmToSecondarySkills[LifeformRealm.DULKHAN_MOUNTAINS].push(SecondarySkill.SUMMON_LESSER_DAEMON);
		realmToSecondarySkills[LifeformRealm.DULKHAN_MOUNTAINS].push(SecondarySkill.SUMMON_ANCIENT_WYRM);
		realmToSecondarySkills[LifeformRealm.MOLTANIA].push(SecondarySkill.HOUSING_DEED_SMALL_COTTAGE);
		realmToSecondarySkills[LifeformRealm.MOLTANIA].push(SecondarySkill.HOUSING_DEED_MEDIUM_TOWER);
		realmToSecondarySkills[LifeformRealm.MOLTANIA].push(SecondarySkill.HOUSING_DEED_LARGE_CASTLE);
		realmToSecondarySkills[LifeformRealm.NETHEREALM].push(SecondarySkill.DEMONIC_BLAST);
		realmToSecondarySkills[LifeformRealm.NETHEREALM].push(SecondarySkill.DEMONIC_WAVE);
		realmToSecondarySkills[LifeformRealm.NETHEREALM].push(SecondarySkill.DEMONIC_NOVA);
		realmToSecondarySkills[LifeformRealm.MAGINCIA].push(SecondarySkill.RADIANT_BLESSING);
		realmToSecondarySkills[LifeformRealm.MAGINCIA].push(SecondarySkill.DIVINE_BLESSING);
		realmToSecondarySkills[LifeformRealm.MAGINCIA].push(SecondarySkill.CELESTIAL_BLESSING);

		secondarySkillToOdds[SecondarySkill.POTION_OF_SWIFTNESS] = 80000;
		secondarySkillToOdds[SecondarySkill.POTION_OF_RECOVERY] = 15000;
		secondarySkillToOdds[SecondarySkill.POTION_OF_GLUTTONY] = 5000;
		secondarySkillToOdds[SecondarySkill.BEGINNER_GARDENING_KIT] = 80000;
		secondarySkillToOdds[SecondarySkill.INTERMEDIATE_GARDENING_KIT] = 15000;
		secondarySkillToOdds[SecondarySkill.EXPERT_GARDENING_KIT] = 5000;
		secondarySkillToOdds[SecondarySkill.SHADOW_WALK] = 80000;
		secondarySkillToOdds[SecondarySkill.SHADOW_ASSAULT] = 15000;
		secondarySkillToOdds[SecondarySkill.SHADOW_OVERLORD] = 5000;
		secondarySkillToOdds[SecondarySkill.SPEAR_OF_FIRE] = 80000;
		secondarySkillToOdds[SecondarySkill.SPEAR_OF_FLAME] = 15000;
		secondarySkillToOdds[SecondarySkill.SPEAR_OF_INFERNO] = 5000;
		secondarySkillToOdds[SecondarySkill.SUMMON_BROWN_BEAR] = 80000;
		secondarySkillToOdds[SecondarySkill.SUMMON_LESSER_DAEMON] = 15000;
		secondarySkillToOdds[SecondarySkill.SUMMON_ANCIENT_WYRM] = 5000;
		secondarySkillToOdds[SecondarySkill.HOUSING_DEED_SMALL_COTTAGE] = 80000;
		secondarySkillToOdds[SecondarySkill.HOUSING_DEED_MEDIUM_TOWER] = 15000;
		secondarySkillToOdds[SecondarySkill.HOUSING_DEED_LARGE_CASTLE] = 5000;
		secondarySkillToOdds[SecondarySkill.DEMONIC_BLAST] = 80000;
		secondarySkillToOdds[SecondarySkill.DEMONIC_WAVE] = 15000;
		secondarySkillToOdds[SecondarySkill.DEMONIC_NOVA] = 5000;
		secondarySkillToOdds[SecondarySkill.RADIANT_BLESSING] = 80000;
		secondarySkillToOdds[SecondarySkill.DIVINE_BLESSING] = 15000;
		secondarySkillToOdds[SecondarySkill.CELESTIAL_BLESSING] = 5000;

        treasureTierToBoost[4] = 15000;
        treasureTierToBoost[5] = 8000;

        staminaPotionId = 1;
        staminaPotionRewardAmount = 3;

        pathToBasePotionPercent[Path.MAGIC] = 15000;
        pathToBasePotionPercent[Path.MAGIC_AND_BC] = 20000;

        treasureBreakOdds = 15000;
    }
}

// Do not change.
struct LifeformInfo {
    uint256 startTime;
    // Used for class/skill decisions
    uint256 requestId;
    address owner;
    Path path;
    LifeformRealm firstRealm;
    LifeformRealm secondRealm;
    // Calculated based on the staked treasures.
    // 100% == 100,000, but could be higher.
    uint256 treasureBoost;
    // Once set, we will know this lifeform is in the process of unstaking. We can then block certain actions from taking place,
    // such as unstaking treasures or trying to start unstaking again.
    uint256 unstakingRequestId;
    uint256[] stakedTreasureIds;
    uint256[] stakedTreasureAmounts;
}

struct UnstakingTreasure {
    uint256 requestId;
    uint256[] unstakingTreasureIds;
    uint256[] unstakingTreasureAmounts;
}

// Can change, only used for a function return parameter.
struct LifeformMetadata {
    LifeformClass lifeformClass;
    OffensiveSkill offensiveSkill;
    uint8 stage;
    SecondarySkill[] secondarySkills;
    string metadataURI;
}

// Can change, used as parameter to function
struct StakeSoLParameters {
    uint256 solId;
    Path path;
    LifeformRealm firstRealm;
    LifeformRealm secondRealm;
    uint256[] treasureIds;
    uint256[] treasureAmounts;
}
