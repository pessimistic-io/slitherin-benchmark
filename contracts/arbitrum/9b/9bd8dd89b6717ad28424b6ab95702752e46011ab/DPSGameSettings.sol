//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./Strings.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./DPSStructs.sol";
import "./DPSInterfaces.sol";

contract DPSGameSettings is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * @notice Voyage config per each voyage type
     */
    mapping(uint256 => CartographerConfig) public voyageConfigPerType;

    /**
     * @notice multiplication skills per each part. each level multiplies by this base skill points
     */
    mapping(FLAGSHIP_PART => uint16) public skillsPerFlagshipPart;

    /**
     * @notice dividing each flagship part into different skills type
     */
    mapping(uint8 => FLAGSHIP_PART[]) public partsForEachSkillType;

    /**
     * @notice flagship base skills
     */
    uint16 public flagshipBaseSkills;

    /**
     * @notice max points a sail can have per skill: strength, luck, navigation.
     * if any goes above this point, then this will act as a hard cap
     */
    uint16 public maxSkillsCap = 630;

    /**
     * @notice max points the causality can generate
     */
    uint16 public maxRollCap = 700;

    /**
     * @notice max points the causality can generate for awarding LockBoxes
     */
    uint16 public maxRollCapLockBoxes = 101;

    /**
     * @notice tmap per buying a voyage
     */
    mapping(uint256 => uint256) public tmapPerVoyage;

    /**
     * @notice gap between 2 consecutive buyVoyages, in seconds.
     */
    uint256 public gapBetweenVoyagesCreation;

    /**
     * @notice in case of emergency to pause different components of the protocol
     * index meaning:
     * - 0 - pause swap tmaps for doubloons
     * - 1 - pause swap doubloons for tmaps
     * - 2 - pause buy a voyage using tmaps
     * - 3 - pause burns a voyage
     * - 4 - pause locks voyages
     * - 5 - pause claiming rewards on Docks
     * - 6 - pause lockToClaimRewards from chests
     * - 7 - pause lock locked boxes
     * - 8 - pause claim locked chests
     * - 9 - pause claiming locked lock boxes
     * - 10 - pause claiming a flagship
     * - 11 - pause repairing a damaged ship
     * - 12 - pause upgrade parts of flagship for doubloons
     * - 13 - pause buy support ships
     */
    uint8[] public paused;

    /**
     * @notice tmaps per doubloons, in wei
     */
    uint256 public tmapPerDoubloon;

    /**
     * @notice max lock boxes that someone can open at a time
     */
    uint256 public maxOpenLockBoxes;

    /**
     * @notice repair flagship cost in doubloons
     */
    uint256 public repairFlagshipCost;

    /**
     * @notice doubloons needed to buy 1 support ship of type SUPPORT_SHIP_TYPE
     */
    mapping(SUPPORT_SHIP_TYPE => uint256) public doubloonsPerSupportShipType;

    /**
     * @notice skill boosts per support ship type
     */
    mapping(SUPPORT_SHIP_TYPE => uint16) public supportShipsSkillBoosts;

    /**
     * @notice skill boosts per artifact type
     */
    mapping(ARTIFACT_TYPE => uint16) public artifactsSkillBoosts;

    /**
     * @notice the max no of ships you can attach per voyage type
     */
    mapping(uint256 => uint8) public maxSupportShipsPerVoyageType;

    /**
     * @notice the amount of doubloons that can be rewarded per chest opened
     */
    mapping(uint256 => uint256) public chestDoubloonRewards;

    /**
     * @notice max rollout that can win a lockbox per chest type (Voyage type)
     * what this means is that out of a roll between 0-10000 if a number between 0 and maxRollPerChest is rolled then
     * the user won a lockbox of the type corresponding with the chest type
     */
    mapping(uint256 => uint256) public maxRollPerChest;

    /**
     * @notice out of 102 distribution of how we will determine the artifact rewards
     */
    mapping(ARTIFACT_TYPE => uint16[2]) public lockBoxesDistribution;

    /**
     * @notice debuffs for every voyage type
     */
    mapping(uint256 => uint16) public voyageDebuffs;

    /**
     * @notice max number of artifacts per voyage type
     */
    mapping(uint16 => uint256) public maxArtifactsPerVoyage;

    /**
     * @notice doubloon price in wei per upgrade part of the flagship per each level as each level can have a diff price
     */
    mapping(uint256 => uint256) public doubloonPerFlagshipUpgradePerLevel;

    event TokenRecovered(address indexed _token, address _destination, uint256 _amount);
    event SetContract(string indexed _target, address _contract);
    event Debug(uint256);

    constructor() {
        voyageConfigPerType[0].minNoOfChests = 4;
        voyageConfigPerType[0].maxNoOfChests = 4;
        voyageConfigPerType[0].minNoOfStorms = 1;
        voyageConfigPerType[0].maxNoOfStorms = 1;
        voyageConfigPerType[0].minNoOfEnemies = 1;
        voyageConfigPerType[0].maxNoOfEnemies = 1;
        voyageConfigPerType[0].totalInteractions = 6;
        voyageConfigPerType[0].gapBetweenInteractions = 60;

        voyageConfigPerType[1].minNoOfChests = 4;
        voyageConfigPerType[1].maxNoOfChests = 6;
        voyageConfigPerType[1].minNoOfStorms = 3;
        voyageConfigPerType[1].maxNoOfStorms = 4;
        voyageConfigPerType[1].minNoOfEnemies = 3;
        voyageConfigPerType[1].maxNoOfEnemies = 4;
        voyageConfigPerType[1].totalInteractions = 12;
        voyageConfigPerType[1].gapBetweenInteractions = 60;

        voyageConfigPerType[2].minNoOfChests = 6;
        voyageConfigPerType[2].maxNoOfChests = 8;
        voyageConfigPerType[2].minNoOfStorms = 5;
        voyageConfigPerType[2].maxNoOfStorms = 6;
        voyageConfigPerType[2].minNoOfEnemies = 5;
        voyageConfigPerType[2].maxNoOfEnemies = 6;
        voyageConfigPerType[2].totalInteractions = 18;
        voyageConfigPerType[2].gapBetweenInteractions = 60;

        voyageConfigPerType[3].minNoOfChests = 8;
        voyageConfigPerType[3].maxNoOfChests = 12;
        voyageConfigPerType[3].minNoOfStorms = 7;
        voyageConfigPerType[3].maxNoOfStorms = 8;
        voyageConfigPerType[3].minNoOfEnemies = 7;
        voyageConfigPerType[3].maxNoOfEnemies = 8;
        voyageConfigPerType[3].totalInteractions = 24;
        voyageConfigPerType[3].gapBetweenInteractions = 60;

        skillsPerFlagshipPart[FLAGSHIP_PART.CANNON] = 10;
        skillsPerFlagshipPart[FLAGSHIP_PART.HULL] = 10;
        skillsPerFlagshipPart[FLAGSHIP_PART.SAILS] = 10;
        skillsPerFlagshipPart[FLAGSHIP_PART.HELM] = 10;
        skillsPerFlagshipPart[FLAGSHIP_PART.FLAG] = 10;
        skillsPerFlagshipPart[FLAGSHIP_PART.FIGUREHEAD] = 10;

        flagshipBaseSkills = 250;

        partsForEachSkillType[uint8(SKILL_TYPE.LUCK)] = [FLAGSHIP_PART.FLAG, FLAGSHIP_PART.FIGUREHEAD];
        partsForEachSkillType[uint8(SKILL_TYPE.NAVIGATION)] = [FLAGSHIP_PART.SAILS, FLAGSHIP_PART.HELM];
        partsForEachSkillType[uint8(SKILL_TYPE.STRENGTH)] = [FLAGSHIP_PART.CANNON, FLAGSHIP_PART.HULL];

        tmapPerVoyage[0] = 1 * 1e18;
        tmapPerVoyage[1] = 2 * 1e18;
        tmapPerVoyage[2] = 3 * 1e18;
        tmapPerVoyage[3] = 4 * 1e18;

        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);
        paused.push(0);

        tmapPerDoubloon = 10;

        maxOpenLockBoxes = 1;

        repairFlagshipCost = 35 * 1e18;

        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.SLOOP_STRENGTH] = 15 * 1e18;
        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.SLOOP_LUCK] = 15 * 1e18;
        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.SLOOP_NAVIGATION] = 15 * 1e18;

        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.CARAVEL_STRENGTH] = 30 * 1e18;
        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.CARAVEL_LUCK] = 30 * 1e18;
        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.CARAVEL_NAVIGATION] = 30 * 1e18;

        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.GALLEON_STRENGTH] = 50 * 1e18;
        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.GALLEON_LUCK] = 50 * 1e18;
        doubloonsPerSupportShipType[SUPPORT_SHIP_TYPE.GALLEON_NAVIGATION] = 50 * 1e18;

        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.SLOOP_STRENGTH] = 10;
        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.SLOOP_LUCK] = 10;
        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.SLOOP_NAVIGATION] = 10;

        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.CARAVEL_STRENGTH] = 30;
        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.CARAVEL_LUCK] = 30;
        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.CARAVEL_NAVIGATION] = 30;

        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.GALLEON_STRENGTH] = 50;
        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.GALLEON_LUCK] = 50;
        supportShipsSkillBoosts[SUPPORT_SHIP_TYPE.GALLEON_NAVIGATION] = 50;

        maxSupportShipsPerVoyageType[0] = 2;
        maxSupportShipsPerVoyageType[1] = 3;
        maxSupportShipsPerVoyageType[2] = 4;
        maxSupportShipsPerVoyageType[3] = 5;

        artifactsSkillBoosts[ARTIFACT_TYPE.NONE] = 0;
        artifactsSkillBoosts[ARTIFACT_TYPE.COMMON_STRENGTH] = 40;
        artifactsSkillBoosts[ARTIFACT_TYPE.COMMON_LUCK] = 40;
        artifactsSkillBoosts[ARTIFACT_TYPE.COMMON_NAVIGATION] = 40;

        artifactsSkillBoosts[ARTIFACT_TYPE.RARE_STRENGTH] = 60;
        artifactsSkillBoosts[ARTIFACT_TYPE.RARE_LUCK] = 60;
        artifactsSkillBoosts[ARTIFACT_TYPE.RARE_NAVIGATION] = 60;

        artifactsSkillBoosts[ARTIFACT_TYPE.EPIC_STRENGTH] = 90;
        artifactsSkillBoosts[ARTIFACT_TYPE.EPIC_LUCK] = 90;
        artifactsSkillBoosts[ARTIFACT_TYPE.EPIC_NAVIGATION] = 90;

        artifactsSkillBoosts[ARTIFACT_TYPE.LEGENDARY_STRENGTH] = 140;
        artifactsSkillBoosts[ARTIFACT_TYPE.LEGENDARY_LUCK] = 140;
        artifactsSkillBoosts[ARTIFACT_TYPE.LEGENDARY_NAVIGATION] = 140;

        chestDoubloonRewards[0] = 45 * 1e18;
        chestDoubloonRewards[1] = 65 * 1e18;
        chestDoubloonRewards[2] = 85 * 1e18;
        chestDoubloonRewards[3] = 105 * 1e18;

        maxRollPerChest[0] = 4;
        maxRollPerChest[1] = 5;
        maxRollPerChest[2] = 8;
        maxRollPerChest[3] = 12;

        lockBoxesDistribution[ARTIFACT_TYPE.COMMON_STRENGTH] = [0, 21];
        lockBoxesDistribution[ARTIFACT_TYPE.COMMON_LUCK] = [22, 43];
        lockBoxesDistribution[ARTIFACT_TYPE.COMMON_NAVIGATION] = [44, 65];

        lockBoxesDistribution[ARTIFACT_TYPE.RARE_STRENGTH] = [66, 72];
        lockBoxesDistribution[ARTIFACT_TYPE.RARE_LUCK] = [73, 79];
        lockBoxesDistribution[ARTIFACT_TYPE.RARE_NAVIGATION] = [80, 86];

        lockBoxesDistribution[ARTIFACT_TYPE.EPIC_STRENGTH] = [87, 89];
        lockBoxesDistribution[ARTIFACT_TYPE.EPIC_LUCK] = [90, 92];
        lockBoxesDistribution[ARTIFACT_TYPE.EPIC_NAVIGATION] = [93, 95];

        lockBoxesDistribution[ARTIFACT_TYPE.LEGENDARY_STRENGTH] = [96, 97];
        lockBoxesDistribution[ARTIFACT_TYPE.LEGENDARY_LUCK] = [98, 99];
        lockBoxesDistribution[ARTIFACT_TYPE.LEGENDARY_NAVIGATION] = [100, 101];

        voyageDebuffs[0] = 0;
        voyageDebuffs[1] = 100;
        voyageDebuffs[2] = 180;
        voyageDebuffs[3] = 260;

        maxArtifactsPerVoyage[uint16(VOYAGE_TYPE.EASY)] = 3;
        maxArtifactsPerVoyage[uint16(VOYAGE_TYPE.MEDIUM)] = 3;
        maxArtifactsPerVoyage[uint16(VOYAGE_TYPE.HARD)] = 3;
        maxArtifactsPerVoyage[uint16(VOYAGE_TYPE.LEGENDARY)] = 3;
        maxArtifactsPerVoyage[uint16(VOYAGE_TYPE.CUSTOM)] = 3;

        doubloonPerFlagshipUpgradePerLevel[0] = 0;
        doubloonPerFlagshipUpgradePerLevel[1] = 0;
        doubloonPerFlagshipUpgradePerLevel[2] = 300 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[3] = 415 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[4] = 530 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[5] = 645 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[6] = 760 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[7] = 875 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[8] = 990 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[9] = 1105 * 1e18;
        doubloonPerFlagshipUpgradePerLevel[10] = 1220 * 1e18;
    }

    function setVoyageConfig(CartographerConfig calldata config, uint256 _type) external onlyOwner {
        voyageConfigPerType[_type] = config;
    }

    function setTmapPerVoyage(uint256 _type, uint256 _amount) external onlyOwner {
        tmapPerVoyage[_type] = _amount;
    }

    function setTmapPerDoubloon(uint256 _amount) external onlyOwner {
        tmapPerDoubloon = _amount;
    }

    function setDoubloonPerFlagshipUpgradePerLevel(uint256 _level, uint256 _amount) external onlyOwner {
        doubloonPerFlagshipUpgradePerLevel[_level] = _amount;
    }

    function setVoyageConfigPerType(uint256 _type, CartographerConfig calldata _config) external onlyOwner {
        voyageConfigPerType[_type].minNoOfChests = _config.minNoOfChests;
        voyageConfigPerType[_type].maxNoOfChests = _config.maxNoOfChests;
        voyageConfigPerType[_type].minNoOfStorms = _config.minNoOfStorms;
        voyageConfigPerType[_type].maxNoOfStorms = _config.maxNoOfStorms;
        voyageConfigPerType[_type].minNoOfEnemies = _config.minNoOfEnemies;
        voyageConfigPerType[_type].maxNoOfEnemies = _config.maxNoOfEnemies;
        voyageConfigPerType[_type].totalInteractions = _config.totalInteractions;
        voyageConfigPerType[_type].gapBetweenInteractions = _config.gapBetweenInteractions;
    }

    function setSkillsPerFlagshipPart(FLAGSHIP_PART _part, uint16 _amount) external onlyOwner {
        skillsPerFlagshipPart[_part] = _amount;
    }

    function setGapBetweenVoyagesCreation(uint256 _newGap) external onlyOwner {
        gapBetweenVoyagesCreation = _newGap;
    }

    function setMaxSkillsCap(uint16 _newCap) external onlyOwner {
        maxSkillsCap = _newCap;
    }

    function setMaxRollCap(uint16 _newCap) external onlyOwner {
        maxRollCap = _newCap;
    }

    function setDoubloonsPerSupportShipType(SUPPORT_SHIP_TYPE _type, uint256 _amount) external onlyOwner {
        doubloonsPerSupportShipType[_type] = _amount;
    }

    function setSupportShipsSkillBoosts(SUPPORT_SHIP_TYPE _type, uint16 _skillPoinst) external onlyOwner {
        supportShipsSkillBoosts[_type] = _skillPoinst;
    }

    function setArtifactSkillBoosts(ARTIFACT_TYPE _type, uint16 _skillPoinst) external onlyOwner {
        artifactsSkillBoosts[_type] = _skillPoinst;
    }

    function setLockBoxesDistribution(ARTIFACT_TYPE _type, uint16[2] calldata _limits) external onlyOwner {
        lockBoxesDistribution[_type] = _limits;
    }

    function setChestDoubloonRewards(uint256 _type, uint256 _rewards) external onlyOwner {
        chestDoubloonRewards[_type] = _rewards;
    }

    function setMaxRollCapLockBoxes(uint16 _maxRollCap) external onlyOwner {
        maxRollCapLockBoxes = _maxRollCap;
    }

    function setMaxRollPerChest(uint256 _type, uint256 _roll) external onlyOwner {
        maxRollPerChest[_type] = _roll;
    }

    function setMaxSupportShipsPerVoyageType(uint256 _type, uint8 _max) external onlyOwner {
        maxSupportShipsPerVoyageType[_type] = _max;
    }

    function setMaxOpenLockBoxes(uint256 _newMax) external onlyOwner {
        maxOpenLockBoxes = _newMax;
    }

    function setRepairFlagshipCost(uint256 _newCost) external onlyOwner {
        repairFlagshipCost = _newCost;
    }

    function setVoyageDebuffs(uint256 _type, uint16 _newDebuff) external onlyOwner {
        voyageDebuffs[_type] = _newDebuff;
    }

    function setMaxArtifactsPerVoyage(VOYAGE_TYPE _type, uint256 _newMax) external onlyOwner {
        maxArtifactsPerVoyage[uint16(_type)] = _newMax;
    }

    function pauseComponent(uint8 _component, uint8 _pause) external onlyOwner {
        paused[_component] = _pause;
    }

    function getSkillTypeOfEachFlagshipPart() public view returns (uint8[7] memory skillTypes) {
        for (uint8 i; i < 3; ++i) {
            for (uint8 j = 0; j < partsForEachSkillType[i].length; ++j) {
                skillTypes[uint256(partsForEachSkillType[i][j])] = i;
            }
        }
    }

    function getSkillsPerFlagshipParts() public view returns (uint16[7] memory skills) {
        skills[uint256(FLAGSHIP_PART.CANNON)] = skillsPerFlagshipPart[FLAGSHIP_PART.CANNON];
        skills[uint256(FLAGSHIP_PART.HULL)] = skillsPerFlagshipPart[FLAGSHIP_PART.HULL];
        skills[uint256(FLAGSHIP_PART.SAILS)] = skillsPerFlagshipPart[FLAGSHIP_PART.SAILS];
        skills[uint256(FLAGSHIP_PART.HELM)] = skillsPerFlagshipPart[FLAGSHIP_PART.HELM];
        skills[uint256(FLAGSHIP_PART.FLAG)] = skillsPerFlagshipPart[FLAGSHIP_PART.FLAG];
        skills[uint256(FLAGSHIP_PART.FIGUREHEAD)] = skillsPerFlagshipPart[FLAGSHIP_PART.FIGUREHEAD];
    }

    function getLockBoxesDistribution(ARTIFACT_TYPE _type) external view returns (uint16[2] memory) {
        return lockBoxesDistribution[_type];
    }

    function isPaused(uint8 _component) external nonReentrant returns (uint8) {
        return paused[_component];
    }

    function isPausedNonReentrant(uint8 _component) external view {
        if (paused[_component] == 1) revert Paused();
    }

    /**
     * @notice Recover NFT sent by mistake to the contract
     * @param _nft the NFT address
     * @param _destination where to send the NFT
     * @param _tokenId the token to want to recover
     */
    function recoverNFT(
        address _nft,
        address _destination,
        uint256 _tokenId
    ) external onlyOwner {
        require(_destination != address(0), "Destination !address(0)");
        IERC721(_nft).safeTransferFrom(address(this), _destination, _tokenId);
        emit TokenRecovered(_nft, _destination, _tokenId);
    }

    /**
     * @notice Recover TOKENS sent by mistake to the contract
     * @param _token the TOKEN address
     * @param _destination where to send the NFT
     */
    function recoverERC20(address _token, address _destination) external onlyOwner {
        require(_destination != address(0), "Destination !address(0)");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_destination, amount);
        emit TokenRecovered(_token, _destination, amount);
    }
}

