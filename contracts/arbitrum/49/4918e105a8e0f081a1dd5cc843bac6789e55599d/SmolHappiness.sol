// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./ISmolMarriage.sol";
import "./ISmolRingStaking.sol";
import "./ISmolHappiness.sol";
import "./ICreatureOwnerResolverRegistry.sol";

/**
 * @title  SmolHappiness contract
 * @author Archethect
 * @notice This contract contains all functionalities for calculating the happiness of Smols
 */
contract SmolHappiness is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ISmolHappiness {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    bool public happinessEnabled;
    uint256 public happinessDecayPerSec;
    uint256 public decayToBeUsed;
    uint256 public maxHappiness;

    ISmolMarriage public smolMarriage;
    ISmolRingStaking public staking;

    mapping(address => mapping(uint256 => Happiness)) public happinessScores;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address operator_,
        address admin_,
        address smolMarriage_,
        address smolRingStaking_,
        uint256 decayToBeUsed_,
        uint256 maxHappiness_
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        require(operator_ != address(0), "SMOLHAPPINESS:ILLEGAL_ADDRESS");
        require(admin_ != address(0), "SMOLHAPPINESS:ILLEGAL_ADDRESS");
        require(smolMarriage_ != address(0), "SMOLHAPPINESS:ILLEGAL_ADDRESS");
        require(smolRingStaking_ != address(0), "SMOLHAPPINESS:ILLEGAL_ADDRESS");
        smolMarriage = ISmolMarriage(smolMarriage_);
        staking = ISmolRingStaking(smolRingStaking_);
        happinessDecayPerSec = 0;
        decayToBeUsed = decayToBeUsed_;
        maxHappiness = maxHappiness_;
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, smolMarriage_);
        _setupRole(OPERATOR_ROLE, smolRingStaking_);
        _setupRole(OPERATOR_ROLE, operator_);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SMOLHAPPINESS:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "SMOLHAPPINESS:ACCESS_DENIED");
        _;
    }

    /**
     * @notice Get the current happiness for a creature
     * @param creature creature object
     */
    function getCurrentHappiness(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (uint256)
    {
        return
            happinessScores[creature.ownerResolver][creature.tokenId].score <
                ((block.timestamp - happinessScores[creature.ownerResolver][creature.tokenId].lastModified) *
                    happinessDecayPerSec)
                ? 0
                : happinessScores[creature.ownerResolver][creature.tokenId].score -
                    ((block.timestamp - happinessScores[creature.ownerResolver][creature.tokenId].lastModified) *
                        happinessDecayPerSec);
    }

    /**
     * @notice get the start happiness of a creature
     * @param creature creature object
     */
    function getStartHappiness(ICreatureOwnerResolverRegistry.Creature memory creature) public view returns (uint256) {
        return happinessScores[creature.ownerResolver][creature.tokenId].score;
    }

    /**
     * @notice Set the happiness of a creature
     * @param creature creature object
     * @param happiness new happiness score to set for the creature
     */
    function setHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 happiness)
        public
        onlyOperator
    {
        require(happiness <= maxHappiness, "SMOLHAPPINESS:HAPPINESS_NOT_WITHIN_BOUNDS");
        if (!happinessScores[creature.ownerResolver][creature.tokenId].valid) {
            happinessScores[creature.ownerResolver][creature.tokenId].valid = true;
        }
        happinessScores[creature.ownerResolver][creature.tokenId].score = happiness;
        happinessScores[creature.ownerResolver][creature.tokenId].lastModified = block.timestamp;
    }

    /**
     * @notice Increase the happiness of a creature
     * @param creature creature object
     * @param happiness amount of happiness to increase
     */
    function increaseHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 happiness)
        public
        onlyOperator
    {
        uint256 newHappiness = getCurrentHappiness(creature) + happiness;
        newHappiness = newHappiness > maxHappiness ? maxHappiness : newHappiness;
        happinessScores[creature.ownerResolver][creature.tokenId].score = newHappiness;
        happinessScores[creature.ownerResolver][creature.tokenId].lastModified = block.timestamp;
        staking.accrueForNewScore(creature);
    }

    /**
     * @notice Decrease the happiness of a creature
     * @param creature creature object
     * @param happiness amount of happiness to decrease
     */
    function decreaseHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 happiness)
        public
        onlyOperator
    {
        uint256 newHappiness = getCurrentHappiness(creature) < happiness
            ? 0
            : getCurrentHappiness(creature) - happiness;
        happinessScores[creature.ownerResolver][creature.tokenId].score = newHappiness;
        happinessScores[creature.ownerResolver][creature.tokenId].lastModified = block.timestamp;
        staking.accrueForNewScore(creature);
    }

    /**
     * @notice Enable happiness
     */
    function enableHappiness() public onlyAdmin {
        require(!happinessEnabled, "SMOLHAPPINESS:HAPPINESS_ALREADY_ACTIVE");
        happinessDecayPerSec = decayToBeUsed;
        happinessEnabled = true;
    }

    /**
     * @notice Disable happiness
     */
    function disableHappiness() public onlyAdmin {
        require(happinessEnabled, "SMOLHAPPINESS:HAPPINESS_ALREADY_INACTIVE");
        happinessDecayPerSec = 0;
        happinessEnabled = false;
    }

    function setDecayFactor(uint256 decay) public onlyAdmin {
        decayToBeUsed = decay;
    }

    function getHappinessDecayPerSec() public view returns (uint256) {
        return happinessDecayPerSec;
    }

    function getMaxHappiness() public view returns (uint256) {
        return maxHappiness;
    }
}

