// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./ISmolMarriage.sol";
import "./ISmolHappiness.sol";
import "./IStakingHappinessBooster.sol";
import "./ICreatureOwnerResolverRegistry.sol";
import "./ICreatureOwnerResolver.sol";
import "./ISmoloveActionsVault.sol";

/**
 * @title  StakingHappinessBooster contract
 * @author Archethect
 * @notice This contract contains all functionalities for boosting happiness of Smols and staking Magic as requirement
 */
contract StakingHappinessBooster is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IStakingHappinessBooster
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    ISmolMarriage public smolMarriage;
    ISmolHappiness public smolHappiness;
    ISmoloveActionsVault public smoloveActionsVault;

    uint256 public magicPricePerPercentInWei;
    address public treasury;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address operator_,
        address admin_,
        address smolMarriage_,
        address smolHappiness_,
        address treasury_,
        address smoloveActionsVault_
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        require(operator_ != address(0), "STAKINGHAPPINESSBOOSTER:ILLEGAL_ADDRESS");
        require(admin_ != address(0), "STAKINGHAPPINESSBOOSTER:ILLEGAL_ADDRESS");
        require(smolMarriage_ != address(0), "STAKINGHAPPINESSBOOSTER:ILLEGAL_ADDRESS");
        require(smolHappiness_ != address(0), "STAKINGHAPPINESSBOOSTER:ILLEGAL_ADDRESS");
        require(treasury_ != address(0), "STAKINGHAPPINESSBOOSTER:ILLEGAL_ADDRESS");
        require(smoloveActionsVault_ != address(0), "STAKINGHAPPINESSBOOSTER:ILLEGAL_ADDRESS");
        smolMarriage = ISmolMarriage(smolMarriage_);
        smolHappiness = ISmolHappiness(smolHappiness_);
        treasury = treasury_;
        smoloveActionsVault = ISmoloveActionsVault(smoloveActionsVault_);
        magicPricePerPercentInWei = 1e18;
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, operator_);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "STAKINGHAPPINESSBOOSTER:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "STAKINGHAPPINESSBOOSTER:ACCESS_DENIED");
        _;
    }

    function boostHappiness(ICreatureOwnerResolverRegistry.Creature memory creature, uint256 percentIncrease)
        public
        nonReentrant
    {
        require(percentIncrease > 0 && percentIncrease <= 100, "STAKINGHAPPINESSBOOSTER:PERCENTAGE_INVALID");
        require(isOwner(msg.sender, creature), "STAKINGHAPPINESSBOOSTER:NOT_OWNER_OF_CREATURE");
        require(smolMarriage.isMarried(creature), "STAKINGHAPPINESSBOOSTER:SMOL_NOT_MARRIED");
        ICreatureOwnerResolverRegistry.Creature memory partner = areCreaturesEqual(
            smolMarriage.getMarriage(creature).creature1,
            creature
        )
            ? smolMarriage.getMarriage(creature).creature2
            : smolMarriage.getMarriage(creature).creature1;
        smolHappiness.increaseHappiness(creature, (percentIncrease * smolHappiness.getMaxHappiness()) / 100);
        smolHappiness.increaseHappiness(partner, (percentIncrease * smolHappiness.getMaxHappiness()) / 100);
        smoloveActionsVault.stake(msg.sender, percentIncrease * magicPricePerPercentInWei);
        emit HappinessBoosted(creature, partner, percentIncrease);
    }

    function setMagicPricePerPercentInWei(uint256 magicPricePerPercentInWei_) public onlyOperator {
        require(magicPricePerPercentInWei_ > 0, "STAKINGHAPPINESSBOOSTER:MAGIC_PRICE_INVALID");
        magicPricePerPercentInWei = magicPricePerPercentInWei_;
    }

    function isOwner(address account, ICreatureOwnerResolverRegistry.Creature memory creature)
        internal
        view
        returns (bool)
    {
        if (ICreatureOwnerResolver(creature.ownerResolver).isOwner(account, creature.tokenId)) {
            return true;
        }
        return false;
    }

    function areCreaturesEqual(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) internal pure returns (bool) {
        if (creature1.ownerResolver == creature2.ownerResolver && creature1.tokenId == creature2.tokenId) {
            return true;
        }
        return false;
    }
}

