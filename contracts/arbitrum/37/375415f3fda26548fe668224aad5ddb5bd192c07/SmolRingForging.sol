// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC1155Upgradeable.sol";

import "./IRandomizer.sol";
import "./ISmolRings.sol";
import "./ISmolRingForging.sol";

/**
 * @title  SmolRingForging contract
 * @author Archethect
 * @notice This contract contains all functionalities for forging rings
 */
contract SmolRingForging is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ISmolRingForging {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using StringsUpgradeable for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    bool public forgeEnabled;
    bool public slotEnabled;
    uint256 public magicSlotPrice;
    uint256 public magicForgePrice;
    uint256 public smolTreasureIdForSlot;
    uint256[] public slotOptions;

    IERC20Upgradeable public magic;
    address public treasury;
    address public smolTreasures;
    ISmolRings public smolRings;
    IRandomizer public randomizer;

    mapping(uint256 => ForgeType) public allowedForges;
    mapping(uint256 => SlotRequest) public ringIdToSlotRequest;
    // Odds out of 100,000
    mapping(uint256 => uint32) public slotIdToOdds;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address smolRings_,
        address magic_,
        address smolTreasures_,
        address randomizer_,
        address treasury_,
        address operator_,
        address admin_
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        require(smolRings_ != address(0), "SMOLRINGFORGING:ILLEGAL_ADDRESS");
        require(magic_ != address(0), "SMOLRINGFORGING:ILLEGAL_ADDRESS");
        require(smolTreasures_ != address(0), "SMOLRINGFORGING:ILLEGAL_ADDRESS");
        require(randomizer_ != address(0), "SMOLRINGFORGING:ILLEGAL_ADDRESS");
        require(treasury_ != address(0), "SMOLRINGFORGING:ILLEGAL_ADDRESS");
        require(operator_ != address(0), "SMOLRINGFORGING:ILLEGAL_ADDRESS");
        require(admin_ != address(0), "SMOLRINGFORGING:ILLEGAL_ADDRESS");
        smolRings = ISmolRings(smolRings_);
        magic = IERC20Upgradeable(magic_);
        smolTreasures = smolTreasures_;
        randomizer = IRandomizer(randomizer_);
        treasury = treasury_;
        smolTreasureIdForSlot = 1;
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, admin_);
        _setupRole(OPERATOR_ROLE, operator_);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SMOLRINGFORGING:ACCESS_DENIED");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "SMOLRINGFORGING:ACCESS_DENIED");
        _;
    }

    modifier nonContractCaller() {
        require(msg.sender == tx.origin, "SMOLRINGFORGING:CONTRACT_CALLER");
        _;
    }

    /**
     * @notice Forge ring into new type
     * @param ringId id of the ring to forge
     * @param ringType type of ring to forge into
     */
    function forgeRing(uint256 ringId, uint256 ringType) external virtual nonReentrant {
        require(forgeEnabled, "SMOLRINGFORGING:FORGING_NOT_ENABLED");
        require(smolRings.ownerOf(ringId) == msg.sender, "SMOLRINGFORGING:NOT_OWNER_OF_RING");
        require(
            allowedForges[ringType].valid && !allowedForges[ringType].slot,
            "SMOLRINGFORGING:TYPE_NOT_ALLOWED_FOR_FORGING"
        );
        require(smolRings.getRingProps(ringId).ringType != ringType, "SMOLRINGFORGING:CANNOT_FORGE_TO_CURRENT_TYPE");
        require(
            smolRings.getTotalRingsPerType(ringType) < allowedForges[ringType].maxForges,
            "SMOLRINGFORGING:MAX_AMOUNT_FOR_TYPE_REACHED"
        );
        require(magicForgePrice > 0, "SMOLRINGFORGING:MAGIC_FORGE_AMOUNT_NOT_SET");

        magic.transferFrom(msg.sender, treasury, magicForgePrice);
        if (allowedForges[ringType].requiredAmount > 0) {
            if (allowedForges[ringType].tokenType == 0) {
                IERC1155Upgradeable(allowedForges[ringType].contractAddress).safeTransferFrom(
                    msg.sender,
                    0x000000000000000000000000000000000000dEaD,
                    allowedForges[ringType].id,
                    allowedForges[ringType].requiredAmount,
                    "0x0"
                );
            } else {
                IERC20Upgradeable(allowedForges[ringType].contractAddress).transferFrom(
                    msg.sender,
                    treasury,
                    allowedForges[ringType].requiredAmount
                );
            }
        }
        smolRings.switchToRingType(ringId, ringType);
        emit RingUpgraded(msg.sender, ringId, ringType);
    }

    function startForgeSlot(uint256 ringId, uint8 oddsMultiplier) external virtual nonReentrant {
        require(forgeEnabled, "SMOLRINGFORGING:FORGING_NOT_ENABLED");
        require(slotEnabled, "SMOLRINGFORGING:SLOT_NOT_ENABLED");
        require(oddsMultiplier > 0 && oddsMultiplier < 6, "SMOLRINGFORGING:ODDS_MULTIPLIER_NOT_IN_RANGE");
        require(smolRings.ownerOf(ringId) == msg.sender, "SMOLRINGFORGING:NOT_OWNER_OF_RING");
        require(ringIdToSlotRequest[ringId].id == 0, "SMOLRINGFORGING:SLOT_IN_PROGRESS");
        require(hasAvailableSlotRingsToForge(), "SMOLRINGFORGING:NOT_ENOUGH_SLOT_TYPES_AVAILABLE");
        require(magicSlotPrice > 0, "SMOLRINGFORGING:MAGIC_SLOT_AMOUNT_NOT_SET");

        magic.transferFrom(msg.sender, treasury, magicSlotPrice * oddsMultiplier);
        IERC1155Upgradeable(smolTreasures).safeTransferFrom(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            smolTreasureIdForSlot,
            1,
            "0x0"
        );

        uint256 _requestId = randomizer.requestRandomNumber();
        ringIdToSlotRequest[ringId].id = _requestId;
        ringIdToSlotRequest[ringId].oddsMultiplier = oddsMultiplier;
        emit StartForgeSlot(msg.sender, _requestId, oddsMultiplier);
    }

    function stopForgeSlot(uint256 ringId) external virtual nonReentrant {
        require(forgeEnabled, "SMOLRINGFORGING:FORGING_NOT_ENABLED");
        require(slotEnabled, "SMOLRINGFORGING:SLOT_NOT_ENABLED");
        require(smolRings.ownerOf(ringId) == msg.sender, "SMOLRINGFORGING:NOT_OWNER_OF_RING");

        uint256 _requestId = ringIdToSlotRequest[ringId].id;
        require(_requestId != 0, "SMOLRINGFORGING:NO_CLAIM_IN_PROGRESS");

        require(randomizer.isRandomReady(_requestId), "SMOLRINGFORGING:RANDOM_NOT_READY");

        uint256[] memory modifiedOdds = changeOdds(ringIdToSlotRequest[ringId].oddsMultiplier);

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        uint256 _rewardResult = _randomNumber % 100000;

        uint256 _topRange = 0;
        for (uint256 i = 0; i < slotOptions.length; i++) {
            _topRange += modifiedOdds[i];
            if (_rewardResult < _topRange) {
                uint256 ringType = (smolRings.getTotalRingsPerType(slotOptions[i]) <=
                    allowedForges[slotOptions[i]].maxForges)
                    ? slotOptions[i]
                    : slotOptions[0];
                smolRings.switchToRingType(ringId, ringType);
                emit RingUpgraded(msg.sender, ringId, ringType);
                break;
            }
        }
        delete ringIdToSlotRequest[ringId];
    }

    function changeOdds(uint8 oddsMultiplier) internal view returns (uint256[] memory) {
        uint256 totalOdds = 0;
        uint256[] memory modifiedOdds = new uint256[](slotOptions.length);
        for (uint256 i = slotOptions.length - 1; i > 0; i--) {
            modifiedOdds[i] = slotIdToOdds[slotOptions[i]];
            if (oddsMultiplier == 2) {
                modifiedOdds[i] = (slotIdToOdds[slotOptions[i]] * 1500) / 1000;
            }
            if (oddsMultiplier == 3) {
                modifiedOdds[i] = slotIdToOdds[slotOptions[i]] * 2;
            }
            if (oddsMultiplier == 4) {
                modifiedOdds[i] = slotIdToOdds[slotOptions[i]] * 4;
            }
            if (oddsMultiplier == 5) {
                modifiedOdds[i] = slotIdToOdds[slotOptions[i]] * 8;
            }
            totalOdds += modifiedOdds[i];
        }
        modifiedOdds[0] = 100000 - totalOdds;
        return modifiedOdds;
    }

    function hasAvailableSlotRingsToForge() public view returns (bool) {
        //Slot is only available when at least 2 ring types are active and has at least 1 free ring available.
        if (slotOptions.length > 1) {
            for (uint256 i = 1; i < slotOptions.length; i++) {
                if (smolRings.getTotalRingsPerType(slotOptions[i]) < allowedForges[slotOptions[i]].maxForges) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * @notice Add allowed forge types
     * @param ringTypes array of ringTypes
     * @param forgeTypes array of forge objects
     */
    function setAllowedForges(uint256[] calldata ringTypes, ForgeType[] calldata forgeTypes) public onlyOperator {
        require(ringTypes.length == forgeTypes.length, "SMOLRINGFORGING:INVALID_ARRAY_LENGTH");
        for (uint256 i = 0; i < forgeTypes.length; i++) {
            allowedForges[ringTypes[i]] = forgeTypes[i];
        }
    }

    /**
     * @notice Remove allowed forge types
     * @param ringTypes array of ringTypes
     */
    function removeAllowedForgeTypes(uint256[] calldata ringTypes) public onlyOperator {
        for (uint256 i = 0; i < ringTypes.length; i++) {
            delete allowedForges[ringTypes[i]];
        }
    }

    function maxForgesPerRingType(uint256 ringType) public view returns (uint256) {
        return allowedForges[ringType].maxForges;
    }

    function setForgeEnabled(bool status) public onlyOperator {
        forgeEnabled = status;
    }

    function setSlotEnabled(bool status) public onlyOperator {
        slotEnabled = status;
    }

    function setSlotOptions(uint256[] calldata _ringIds, uint32[] calldata _slotOdds) public onlyOperator {
        require(_ringIds.length == _slotOdds.length, "SMOLRINGFORGING:BAD_ARRAY_LENGTH");
        delete slotOptions;
        uint256 totalOdds = 0;
        for (uint256 i = 0; i < _ringIds.length; i++) {
            totalOdds += _slotOdds[i];
            slotOptions.push(_ringIds[i]);
            slotIdToOdds[_ringIds[i]] = _slotOdds[i];
        }
        require(totalOdds == 100000, "SMOLRINGFORGING:TOTAL_ODDS_NOT_CORRECT");
    }

    function setMagicSlotPrice(uint256 _magicSlotPrice) public onlyOperator {
        magicSlotPrice = _magicSlotPrice;
    }

    function setMagicForgePrice(uint256 _magicForgePrice) public onlyOperator {
        magicForgePrice = _magicForgePrice;
    }

    function setSmolTreasureIdForSlot(uint256 _smolTreasureIdForSlot) public onlyOperator {
        smolTreasureIdForSlot = _smolTreasureIdForSlot;
    }

    function getAllowedForges(uint256 index) public view returns (ForgeType memory) {
        return allowedForges[index];
    }

    function setRandomizer(address _randomizer) public onlyOperator {
        randomizer = IRandomizer(_randomizer);
    }
}

