// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./StringsUpgradeable.sol";

import "./ISmolMarriage.sol";
import "./ISmolRings.sol";
import "./ISmolHappiness.sol";
import "./ISmolRingStaking.sol";
import "./ICreatureOwnerResolver.sol";
import "./ICreatureOwnerResolverRegistry.sol";
import "./ISmoloveActionsVault.sol";
import "./IAtlasMine.sol";
import "./ISmolverseFlywheelVault.sol";

/**
 * @title  SmolMarriage contract
 * @author Archethect
 * @notice This contract contains all functionalities for marrying Smols
 */
contract SmolMarriage is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ISmolMarriage {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using StringsUpgradeable for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    bool public marriageEnabled;
    uint256 public divorcePenaltyFee;
    uint256 public divorceCoolOff;
    uint256 public marriageStakingPriceInWei;

    address public treasury;
    ICreatureOwnerResolverRegistry public creatureOwnerResolverRegistry;
    IERC20Upgradeable public magic;
    ISmolRingStaking public staking;
    ISmolRings public smolRings;
    ISmolHappiness public smolHappiness;
    ISmoloveActionsVault public smoloveActionsVault;

    mapping(address => mapping(uint256 => Marriage)) public marriages;
    mapping(address => mapping(uint256 => RequestedMarriage)) public marriageRequest;
    mapping(address => mapping(uint256 => address)) public marriageRequestToAddress;
    mapping(address => mapping(uint256 => RequestedDivorce)) public divorceRequest;
    mapping(address => mapping(uint256 => RequestedDivorce)) public pendingDivorceRequest;
    mapping(address => mapping(uint256 => ICreatureOwnerResolverRegistry.Creature[])) public pendingMarriageRequests;
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => uint256))))
        public pendingMarriageRequestsLUT;
    mapping(address => mapping(uint256 => RedeemableDivorce[])) public redeemableDivorces;
    mapping(address => mapping(uint256 => uint256)) public lastDivorced;

    //----------- Marriage Flywheel Staking Upgrade ---------//
    ISmolverseFlywheelVault public smolverseFlywheelVault;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address creatureOwnerResolverRegistry_,
        address magic_,
        address operator_,
        address admin_,
        address treasury_,
        address staking_,
        address smolRings_,
        address smolHappiness_,
        address smoloveActionsVault_
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        require(creatureOwnerResolverRegistry_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(magic_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(operator_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(admin_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(treasury_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(staking_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(smolRings_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(smolHappiness_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        require(smoloveActionsVault_ != address(0), "SMOLMARRIAGE:ILLEGAL_ADDRESS");
        creatureOwnerResolverRegistry = ICreatureOwnerResolverRegistry(creatureOwnerResolverRegistry_);
        magic = IERC20Upgradeable(magic_);
        staking = ISmolRingStaking(staking_);
        smolRings = ISmolRings(smolRings_);
        smolHappiness = ISmolHappiness(smolHappiness_);
        smoloveActionsVault = ISmoloveActionsVault(smoloveActionsVault_);
        treasury = treasury_;
        divorcePenaltyFee = 20e18;
        marriageStakingPriceInWei = 80e18;
        divorceCoolOff = 2 weeks;
        magic.approve(address(this), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, operator_);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SMOLMARRIAGE:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "SMOLMARRIAGE:ACCESS_DENIED");
        _;
    }

    modifier checkFlywheelBalance(ICreatureOwnerResolverRegistry.Creature memory creature) {
        uint256 allowance = smolverseFlywheelVault.getAllowanceForToken(creature.ownerResolver);
        uint256 currentlyRemaining = smolverseFlywheelVault.remainingStakeableAmount(msg.sender);
        uint256 currentlyStaked = smolverseFlywheelVault.getStakedAmount(msg.sender);
        uint256 remainingAfterSubstraction = allowance <= currentlyRemaining ? currentlyRemaining - allowance : 0;
        require(currentlyStaked <= remainingAfterSubstraction, "SMOLMARRIAGE:CANNOT_DIVORCE_WHEN_STAKED_IN_FLYWHEEL");
        _;
    }

    /**
     * @notice Request marriage to another creature
     * @param creature1 creature object 1
     * @param creature2 creature object 2
     * @param ring1 id of ring 2
     * @param ring2 id of ring 2
     */
    function requestMarriage(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        uint256 ring1,
        uint256 ring2
    ) public {
        require(
            isAllowedToMarry(creature1) && isAllowedToMarry(creature2),
            "SMOLMARRIAGE:ONLY_ALLOWED_TO_MARRY_WITH_ALLOWED_CREATURES"
        );
        require(!areCreaturesEqual(creature1, creature2), "SMOLMARRIAGE:CANNOT_MARRY_YOURSELF");
        require(ring1 != ring2, "SMOLMARRIAGE:CANNOT_USE_THE_SAME_RING");
        require(!isMarried(creature1) && !isMarried(creature2), "SMOLMARRIAGE:ONLY_ALLOWED_TO_MARRY_1_PARTNER");
        require(!hasMarriageRequest(creature1), "SMOLMARRIAGE:ONLY_1_MARRIAGE_REQUEST_ALLOWED");
        require(
            !marriageRequest[creature2.ownerResolver][creature2.tokenId].valid ||
                !areCreaturesEqual(marriageRequest[creature2.ownerResolver][creature2.tokenId].partner, creature1),
            "SMOLMARRIAGE:MARRIAGE_REQUEST_ALREADY_EXISTS_FOR_SMOL"
        );
        require(isOwner(msg.sender, creature1), "SMOLMARRIAGE:NOT_OWNER_OF_CREATURE");
        require(
            smolRings.getApproved(ring1) == address(staking) ||
                smolRings.isApprovedForAll(msg.sender, address(staking)),
            "SMOLMARRIAGE:NO_ALLOWANCE_FOR_STAKING_CONTRACT_SET"
        );
        require(smolRings.ownerOf(ring1) == msg.sender, "SMOLMARRIAGE:NOT_OWNER_OF_RING");
        require(
            magic.allowance(msg.sender, address(smoloveActionsVault)) >= marriageStakingPriceInWei,
            "SMOLMARRIAGE:NO_ALLOWANCE_FOR_MAGIC_STAKING_CONTRACT_SET"
        );
        require(magic.balanceOf(msg.sender) >= marriageStakingPriceInWei, "SMOLMARRIAGE:NOT_ENOUGH_MAGIC_IN_WALLET");
        marriageRequest[creature1.ownerResolver][creature1.tokenId] = RequestedMarriage(true, creature2, ring1, ring2);
        pendingMarriageRequests[creature2.ownerResolver][creature2.tokenId].push(creature1);
        pendingMarriageRequestsLUT[creature2.ownerResolver][creature2.tokenId][creature1.ownerResolver][
            creature1.tokenId
        ] = pendingMarriageRequests[creature2.ownerResolver][creature2.tokenId].length - 1;
        marriageRequestToAddress[creature1.ownerResolver][creature1.tokenId] = msg.sender;
        emit RequestMarriage(creature1, creature2, ring1, ring2);
    }

    /**
     * @notice Cancel an existing marriage request
     * @param creature1 creature object 1
     * @param creature2 creature object 2
     */
    function cancelMarriageRequest(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) public {
        require(isOwner(msg.sender, creature1) || isOwner(msg.sender, creature2), "SMOLMARRIAGE:NOT_OWNER_OF_CREATURE");
        require(
            (marriageRequest[creature1.ownerResolver][creature1.tokenId].valid &&
                areCreaturesEqual(marriageRequest[creature1.ownerResolver][creature1.tokenId].partner, creature2)) ||
                (marriageRequest[creature2.ownerResolver][creature2.tokenId].valid &&
                    areCreaturesEqual(marriageRequest[creature2.ownerResolver][creature2.tokenId].partner, creature1)),
            "SMOLMARRIAGE:NON_EXISTANT_MARRIAGE_REQUEST"
        );
        if (!hasMarriageRequest(creature1)) {
            //Switch smols around
            ICreatureOwnerResolverRegistry.Creature memory newCreature1 = creature2;
            creature2 = creature1;
            creature1 = newCreature1;
        }
        delete marriageRequest[creature1.ownerResolver][creature1.tokenId];
        uint256 rowToDelete = pendingMarriageRequestsLUT[creature2.ownerResolver][creature2.tokenId][
            creature1.ownerResolver
        ][creature1.tokenId];
        ICreatureOwnerResolverRegistry.Creature memory requestToMove = pendingMarriageRequests[creature2.ownerResolver][
            creature2.tokenId
        ][pendingMarriageRequests[creature2.ownerResolver][creature2.tokenId].length - 1];
        pendingMarriageRequests[creature2.ownerResolver][creature2.tokenId][rowToDelete] = requestToMove;
        pendingMarriageRequestsLUT[creature2.ownerResolver][creature2.tokenId][requestToMove.ownerResolver][
            requestToMove.tokenId
        ] = rowToDelete;
        pendingMarriageRequests[creature2.ownerResolver][creature2.tokenId].pop();
        delete pendingMarriageRequestsLUT[creature2.ownerResolver][creature2.tokenId][creature1.ownerResolver][
            creature1.tokenId
        ];
        emit CancelMarriageRequest(creature1, creature2);
    }

    /**
     * @notice Request a divorce
     * @param creature creature object of the creature that requests a divorce
     */
    function requestDivorce(ICreatureOwnerResolverRegistry.Creature memory creature) public {
        require(isOwner(msg.sender, creature), "SMOLMARRIAGE:NOT_OWNER_OF_CREATURE");
        require(isMarried(creature), "SMOLMARRIAGE:CREATURE_NOT_MARRIED");
        require(
            !hasDivorceRequest(creature) && !hasPendingDivorceRequest(creature),
            "SMOLMARRIAGE:DIVORCE_REQUEST_ALREADY_EXISTS"
        );
        ICreatureOwnerResolverRegistry.Creature memory partner = areCreaturesEqual(
            marriages[creature.ownerResolver][creature.tokenId].creature1,
            creature
        )
            ? marriages[creature.ownerResolver][creature.tokenId].creature2
            : marriages[creature.ownerResolver][creature.tokenId].creature1;
        divorceRequest[creature.ownerResolver][creature.tokenId] = RequestedDivorce(true, partner);
        pendingDivorceRequest[partner.ownerResolver][partner.tokenId] = RequestedDivorce(true, creature);
        emit DivorceRequest(creature, partner);
    }

    /**
     * @notice Cancel a divorce request
     * @param creature1 creature object 1
     * @param creature2 creature object 2
     */
    function cancelDivorceRequest(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) public {
        require(
            isOwner(msg.sender, creature1) || isOwner(msg.sender, creature2),
            "SMOLMARRIAGE:ONLY_CREATURE_OWNER_CAN_CANCEL_DIVORCE_REQUEST"
        );
        require(
            areCreaturesEqual(divorceRequest[creature1.ownerResolver][creature1.tokenId].partner, creature2) ||
                areCreaturesEqual(divorceRequest[creature2.ownerResolver][creature2.tokenId].partner, creature1),
            "SMOLMARRIAGE:NON_EXISTANT_DIVORCE_REQUEST"
        );
        if (!hasDivorceRequest(creature1)) {
            //Switch smols around
            ICreatureOwnerResolverRegistry.Creature memory newCreature1 = creature2;
            creature2 = creature1;
            creature1 = newCreature1;
        }
        delete divorceRequest[creature1.ownerResolver][creature1.tokenId];
        delete pendingDivorceRequest[creature2.ownerResolver][creature2.tokenId];
        emit CancelDivorceRequest(creature1, creature2);
    }

    /**
     * @notice Marry 2 creatures. Requires existing marriage request
     * @param creature1 creature object 1
     * @param creature2 creature object 2
     * @param ring1 id of ring 2
     * @param ring2 id of ring 2
     * @param partner Address of owner of creature 2
     */
    function marry(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2,
        uint256 ring1,
        uint256 ring2,
        address partner
    ) public nonReentrant {
        require(marriageEnabled, "SMOLMARRIAGE:MARRIAGE_DISABLED");
        require(!areCreaturesEqual(creature1, creature2), "SMOLMARRIAGE:CANNOT_MARRY_YOURSELF");
        require(ring1 != ring2, "SMOLMARRIAGE:CANNOT_USE_THE_SAME_RING");
        require(
            isAllowedToMarry(creature1) && isAllowedToMarry(creature2),
            "SMOLMARRIAGE:ONLY_ALLOWED_TO_MARRY_WITH_ALLOWED_CREATURES"
        );
        require(
            lastDivorced[creature1.ownerResolver][creature1.tokenId] + divorceCoolOff < block.timestamp,
            "SMOLMARRIAGE:RECENTLY_DIVORCED"
        );
        require(
            lastDivorced[creature2.ownerResolver][creature2.tokenId] + divorceCoolOff < block.timestamp,
            "SMOLMARRIAGE:RECENTLY_DIVORCED"
        );
        require(
            isOwner(msg.sender, creature1) &&
                isOwner(partner, creature2) &&
                smolRings.ownerOf(ring1) == msg.sender &&
                smolRings.ownerOf(ring2) == partner,
            "SMOLMARRIAGE:INCORRECT_OWNER_OF_CREATURE_AND_RING"
        );
        require(
            marriageRequestToAddress[creature2.ownerResolver][creature2.tokenId] == partner,
            "SMOLMARRIAGE:CURRENT_CREATURE_OWNER_IS_NOT_PROPOSER"
        );
        require(
            (smolRings.getApproved(ring1) == address(staking) ||
                smolRings.isApprovedForAll(msg.sender, address(staking))) &&
                (smolRings.getApproved(ring2) == address(staking) ||
                    smolRings.isApprovedForAll(partner, address(staking))),
            "SMOLMARRIAGE:NO_ALLOWANCE_FOR_RING_STAKING_CONTRACT_SET"
        );
        require(
            marriageRequest[creature2.ownerResolver][creature2.tokenId].ring == ring2 &&
                areCreaturesEqual(marriageRequest[creature2.ownerResolver][creature2.tokenId].partner, creature1) &&
                marriageRequest[creature2.ownerResolver][creature2.tokenId].partnerRing == ring1,
            "SMOLMARRIAGE:NON_EXISTANT_MARRIAGE_REQUEST"
        );
        require(
            (magic.allowance(msg.sender, address(smoloveActionsVault)) >= marriageStakingPriceInWei &&
                magic.allowance(partner, address(smoloveActionsVault)) >= marriageStakingPriceInWei),
            "SMOLMARRIAGE:NO_ALLOWANCE_FOR_MAGIC_STAKING_CONTRACT_SET"
        );
        require(
            (magic.balanceOf(msg.sender) >= marriageStakingPriceInWei &&
                magic.balanceOf(partner) >= marriageStakingPriceInWei),
            "SMOLMARRIAGE:NOT_ENOUGH_MAGIC_IN_WALLET"
        );
        smoloveActionsVault.stake(msg.sender, marriageStakingPriceInWei);
        smoloveActionsVault.stake(partner, marriageStakingPriceInWei);
        smolHappiness.setHappiness(creature1, smolHappiness.getMaxHappiness());
        smolHappiness.setHappiness(creature2, smolHappiness.getMaxHappiness());
        staking.stake(ring1, creature1, ring2, creature2, msg.sender, partner);
        Marriage memory marriage = Marriage(true, creature1, creature2, ring1, ring2, block.timestamp);
        marriages[creature1.ownerResolver][creature1.tokenId] = marriage;
        marriages[creature2.ownerResolver][creature2.tokenId] = marriage;
        delete marriageRequest[creature2.ownerResolver][creature2.tokenId];
        uint256 rowToDelete = pendingMarriageRequestsLUT[creature1.ownerResolver][creature1.tokenId][
            creature2.ownerResolver
        ][creature2.tokenId];
        ICreatureOwnerResolverRegistry.Creature memory requestToMove = pendingMarriageRequests[creature1.ownerResolver][
            creature1.tokenId
        ][pendingMarriageRequests[creature1.ownerResolver][creature1.tokenId].length - 1];
        pendingMarriageRequests[creature1.ownerResolver][creature1.tokenId][rowToDelete] = requestToMove;
        pendingMarriageRequestsLUT[creature1.ownerResolver][creature1.tokenId][requestToMove.ownerResolver][
            requestToMove.tokenId
        ] = rowToDelete;
        pendingMarriageRequests[creature1.ownerResolver][creature1.tokenId].pop();
        delete pendingMarriageRequestsLUT[creature1.ownerResolver][creature1.tokenId][creature2.ownerResolver][
            creature2.tokenId
        ];
        emit Married(creature1, creature2, ring1, ring2, block.timestamp);
    }

    /**
     * @notice Divorce 2 creatures. Requires existing divorce request for free divorce
     * @param creature1 creature object 1
     * @param creature2 creature object 2
     */
    function divorce(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) public nonReentrant{
        require(isOwner(msg.sender, creature1), "SMOLMARRIAGE:NOT_OWNER_OF_CREATURE");
        require(areMarried(creature1, creature2), "SMOLMARRIAGE:CREATURES_NOT_MARRIED");
        uint256 penaltyFee;
        if (!divorceRequest[creature2.ownerResolver][creature2.tokenId].valid) {
            //Pay divorce fee
            penaltyFee =
                (divorcePenaltyFee *
                    smolRings.ringRarity(marriages[creature1.ownerResolver][creature1.tokenId].ring1) *
                    50) /
                100000;
            magic.transferFrom(msg.sender, treasury, penaltyFee);
            magic.transferFrom(msg.sender, address(this), penaltyFee);
        } else {
            delete divorceRequest[creature2.ownerResolver][creature2.tokenId];
            delete pendingDivorceRequest[creature1.ownerResolver][creature1.tokenId];
        }
        uint256 redeemRing = marriages[creature1.ownerResolver][creature1.tokenId].ring1;
        uint256 pendingRing = marriages[creature1.ownerResolver][creature1.tokenId].ring2;
        if (areCreaturesEqual(marriages[creature1.ownerResolver][creature1.tokenId].creature2, creature1)) {
            redeemRing = marriages[creature1.ownerResolver][creature1.tokenId].ring2;
            pendingRing = marriages[creature1.ownerResolver][creature1.tokenId].ring1;
        }
        redeemableDivorces[creature2.ownerResolver][creature2.tokenId].push(
            RedeemableDivorce(true, pendingRing, penaltyFee)
        );
        staking.unstake(redeemRing, pendingRing, creature1, creature2, msg.sender);
        smolHappiness.setHappiness(creature1, 0);
        smolHappiness.setHappiness(creature2, 0);
        delete marriages[creature1.ownerResolver][creature1.tokenId];
        delete marriages[creature2.ownerResolver][creature2.tokenId];
        lastDivorced[creature1.ownerResolver][creature1.tokenId] = block.timestamp;
        lastDivorced[creature2.ownerResolver][creature2.tokenId] = block.timestamp;
        emit Divorced(creature1, creature2);
    }

    /**
     * @notice Redeem the rings of the partner of the divorce initiator
     * @param creature creature object of creature to redeem the rings from
     */
    function redeemDivorcedRings(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        nonReentrant
    {
        require(isOwner(msg.sender, creature), "SMOLMARRIAGE:NOT_OWNER_OF_CREATURE");
        require(
            redeemableDivorces[creature.ownerResolver][creature.tokenId].length > 0,
            "SMOLMARRIAGE:NO_PENDING_RING_AFTER_DIVORCE"
        );
        uint256 penaltyFee = 0;
        for (uint256 i = 0; i < redeemableDivorces[creature.ownerResolver][creature.tokenId].length; i++) {
            if (redeemableDivorces[creature.ownerResolver][creature.tokenId][i].valid) {
                if (redeemableDivorces[creature.ownerResolver][creature.tokenId][i].penaltyFee > 0) {
                    penaltyFee += redeemableDivorces[creature.ownerResolver][creature.tokenId][i].penaltyFee;
                }
                staking.withdrawRing(
                    redeemableDivorces[creature.ownerResolver][creature.tokenId][i].ring,
                    creature,
                    msg.sender
                );
                emit RedeemedDivorcedRing(
                    creature,
                    redeemableDivorces[creature.ownerResolver][creature.tokenId][i].ring,
                    redeemableDivorces[creature.ownerResolver][creature.tokenId][i].penaltyFee
                );
            }
        }
        delete redeemableDivorces[creature.ownerResolver][creature.tokenId];
        if (penaltyFee > 0) {
            magic.transferFrom(address(this), msg.sender, penaltyFee);
        }
    }

    function setMarriageStakingPriceInWei(uint256 marriageStakingPriceInWei_) external onlyOperator {
        marriageStakingPriceInWei = marriageStakingPriceInWei_;
    }

    function setDivorcePenaltyFee(uint256 divorcePenaltyFee_) external onlyOperator {
        divorcePenaltyFee = divorcePenaltyFee_;
    }

    function setDivorceCoolOff(uint256 divorceCoolOff_) external onlyOperator {
        divorceCoolOff = divorceCoolOff_;
    }

    function areMarried(
        ICreatureOwnerResolverRegistry.Creature memory creature1,
        ICreatureOwnerResolverRegistry.Creature memory creature2
    ) public view returns (bool) {
        return (marriages[creature1.ownerResolver][creature1.tokenId].valid &&
            (
                areCreaturesEqual(
                    marriages[creature1.ownerResolver][creature1.tokenId].creature1,
                    marriages[creature2.ownerResolver][creature2.tokenId].creature1
                )
            ));
    }

    function isMarried(ICreatureOwnerResolverRegistry.Creature memory creature) public view returns (bool) {
        return marriages[creature.ownerResolver][creature.tokenId].valid;
    }

    function getMarriage(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (Marriage memory)
    {
        return marriages[creature.ownerResolver][creature.tokenId];
    }

    function hasMarriageRequest(ICreatureOwnerResolverRegistry.Creature memory creature) public view returns (bool) {
        return marriageRequest[creature.ownerResolver][creature.tokenId].valid;
    }

    function getPendingMarriageRequests(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (ICreatureOwnerResolverRegistry.Creature[] memory)
    {
        return pendingMarriageRequests[creature.ownerResolver][creature.tokenId];
    }

    function getRedeemableDivorces(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (RedeemableDivorce[] memory)
    {
        return redeemableDivorces[creature.ownerResolver][creature.tokenId];
    }

    function hasPendingMarriageRequests(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (bool)
    {
        return (pendingMarriageRequests[creature.ownerResolver][creature.tokenId].length > 0);
    }

    function hasDivorceRequest(ICreatureOwnerResolverRegistry.Creature memory creature) public view returns (bool) {
        return divorceRequest[creature.ownerResolver][creature.tokenId].valid;
    }

    function hasPendingDivorceRequest(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (bool)
    {
        return pendingDivorceRequest[creature.ownerResolver][creature.tokenId].valid;
    }

    function getPendingDivorceRequest(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (ICreatureOwnerResolverRegistry.Creature memory)
    {
        return pendingDivorceRequest[creature.ownerResolver][creature.tokenId].partner;
    }

    function getMarriageProposerAddressForCreature(ICreatureOwnerResolverRegistry.Creature memory creature)
        public
        view
        returns (address)
    {
        return marriageRequestToAddress[creature.ownerResolver][creature.tokenId];
    }

    function setMarriageEnabled(bool status) public onlyOperator {
        marriageEnabled = status;
    }

    function isAllowedToMarry(ICreatureOwnerResolverRegistry.Creature memory creature) public view returns (bool) {
        if (creatureOwnerResolverRegistry.isAllowed(creature.ownerResolver)) {
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

    /**
    * @dev Set the smolverse flywheel vault
    */
    function setSmolverseFlywheelVault(address smolverseFlywheelVault_) external onlyAdmin {
        require(smolverseFlywheelVault_ != address(0));
        smolverseFlywheelVault = ISmolverseFlywheelVault(smolverseFlywheelVault_);
    }
}

