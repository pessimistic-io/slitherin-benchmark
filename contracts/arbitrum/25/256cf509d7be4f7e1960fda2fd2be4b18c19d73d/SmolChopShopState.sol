//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleProofUpgradeable.sol";
import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./IERC721.sol";
import "./IERC20Upgradeable.sol";
import "./IERC1155Upgradeable.sol";
import "./ISmolChopShop.sol";
import "./UtilitiesV2Upgradeable.sol";
import "./ISmolRacingTrophies.sol";
import "./SmolRacing.sol";

/// @title Smol Chop Shop State
/// @author Gearhart
/// @notice Shared storage layout for SmolChopShop.

abstract contract SmolChopShopState is Initializable, UtilitiesV2Upgradeable, ISmolChopShop {

    // -------------------------------------------------------------
    //                   Mappings & Variables
    // -------------------------------------------------------------

    uint256 internal constant UPGRADE_TYPE_OFFSET = 1_000_000;
    uint256 internal constant UPGRADE_LIMITED_OFFER_ID_BIT_OFFSET = 32;
    uint256 internal constant UPGRADE_GROUP_ID_BIT_OFFSET = 128;
    uint256 internal constant UPGRADE_UPGRADE_TYPE_BIT_OFFSET = 184;
    uint256 internal constant UPGRADE_VALID_SKIN_BIT_OFFSET = 192;

    /// @notice smolRacing contract for ownership checks while staking/racing
    SmolRacing public smolRacing;

    /// @notice smolRacingTrophies ERC1155 NFT contract
    ISmolRacingTrophies public racingTrophies;

    /// @notice smolCars ERC721 NFT contract
    IERC721 public smolCars;

    /// @notice swolercycle ERC721 NFT contract
    IERC721 public swolercycles;

    // -------------------------------------------------------------
    //                   Trophy Metadata
    // -------------------------------------------------------------

    /// @notice Id number of ERC1155 token from racing trophies contract that is used for upgrade payment and exchange
    /// @dev used to set values for other trophies and must be set for contract to function
    uint256 public coconutId;

    /// @notice Value associated with each trophy id denominated in Coconuts.
    /// @dev must be set before trophies can be exchanged
    mapping (uint256 => uint256) 
        public trophyExchangeValue;

    /// @notice Mapping for keeping track of how many Coconuts user spent in total.
    /// @dev user address => total amount spent at smolChopShop
    mapping (address => uint256) 
        public userToTotalAmountSpent;

    // -------------------------------------------------------------
    //                   Merkle Verifications
    // -------------------------------------------------------------

    /// @notice mapping for keeping track of user WL allocation during buyExclusiveUpgrade. 
    /// @dev user address => upgrade Id => WL spot claimed or not
    mapping (address => mapping(uint256 => bool))
        public userAllocationClaimed;

    /// @notice Mapping for keeping track of user WL allocation for a subgroup within a limited offer.
    /// @dev user address => limitedOffer id => subgroup id => WL spot claimed or not
    mapping (address => mapping (uint256 => mapping(uint256 => bool)))
        public userLimitedOfferAllocationClaimed;

    /// @notice Mapping for keeping track of vehicle WL allocation for global claim and special event claim.
    /// @dev vehicle address => vehicle id => limitedOffer id => subgroup id => WL spot claimed or not
    mapping (address => mapping(uint256 => mapping (uint256 => mapping(uint256 => bool))))
        public vehicleLimitedOfferAllocationClaimed;

    // -------------------------------------------------------------
    //                   Limited Offers
    // -------------------------------------------------------------

    /// @notice number for keeping track of current limited offer and opening a new level of subgroups (without erasing the last) for specialEventClaim (when incremented)
    /// @dev used when creating a new special event with subgroups. LimitedOfferId = 0 is reserved for globalClaims ONLY. 
    uint256 public latestLimitedOffer;

    // Used to track the pool of available upgrades to choose from for specialEventClaim and globalClaim
    // All subgroups for each limitedOfferId > 0 represent seperate pools of upgrades available for a given special event.
    // Each subgroup for limitedOfferId = 0 represents a seperate global claim.
    // limitedOffer id => subgroup id => ids that are within that group
    mapping (uint256 => mapping (uint256 => EnumerableSetUpgradeable.UintSet))
        internal limitedOfferToGroupToIds;

    // -------------------------------------------------------------
    //                   UpgradeType Metadata
    // -------------------------------------------------------------


    /// @notice Base URI to be concatenated with Upgrade ID + suffix
    /// @dev could also hold individual URIs or SVGs in upgrade struct but having IPFS folders is cheaper. dev has option of using either method
    string public baseURI;

    /// @notice Suffix URI to be concatenated with base + Upgrade ID
    /// @dev ex: ".png" or ".json"
    string public suffixURI;

    /// @notice Highest id number currently in use for each Upgrade type
    /// @dev used to keep track of how many upgrades of each type have been created
    mapping (UpgradeType => uint256) 
        public upgradeTypeToLastId;

    // -------------------------------------------------------------
    //                   Upgrade Metadata
    // -------------------------------------------------------------

    // mapping that holds a struct containing Upgrade info for each id
    // Upgrade id => Upgrade struct 
    mapping (uint256 => Upgrade) 
        internal upgradeToInfo;

    // Set of all Upgrades currently for sale/claim
    EnumerableSetUpgradeable.UintSet internal upgradeIdsForSale;

    // -------------------------------------------------------------
    //                   Vehicle Metadata
    // -------------------------------------------------------------

    // mapping to array of all upgrades that have been unlocked for a given vehicle
    // vehicle collection address => vehicle id => Enumerable Uint Set of all unlocked upgrades
    mapping (address => mapping (uint256 => EnumerableSetUpgradeable.UintSet))
        internal upgradeIdsUnlockedForVehicle;

    // mapping to struct holding ids of currently equiped upgrades for a given vehicle
    // vehicle collection address => vehichle id => Vehicle struct
    mapping (address => mapping (uint256 => Vehicle))
        internal vehicleToEquippedUpgrades;

    // -------------------------------------------------------------
    //                         Internal
    // -------------------------------------------------------------

    /* solhint-disable no-inline-assembly */
    function _getLimitedOfferIdAndGroupForUpgrade(uint256 _upgradeId) internal view returns(uint32 limitedOfferId_, uint8 groupId_){
        uint256 _mask32 = type(uint32).max;
        assembly {
            mstore(0, _upgradeId)
            mstore(32, upgradeToInfo.slot)
            let slot := keccak256(0, 64)

            let upgradeSlot1 := sload(slot)
            // Get the limitedOfferId from the Upgrade struct by offsetting the first 32 bits (amountClaimed value)
            // And only getting the first 32 bits of that part of the slot (for limitedOfferId)
            // shr will delete the least significant 32 bits of the slot data, which is the value of Upgrade.amountClaimed
            // and with the full value of a 32 bit uint will only save the data from the remaining slot that overlaps
            //  the mask with the actual stored value
            limitedOfferId_ := and(shr(UPGRADE_LIMITED_OFFER_ID_BIT_OFFSET, upgradeSlot1), _mask32)
            groupId_ := and(shr(UPGRADE_GROUP_ID_BIT_OFFSET, upgradeSlot1), _mask32)
        }
    }

    function _getTypeForUpgrade(uint256 _upgradeId) internal view returns(UpgradeType upgradeType_){
        uint256 _mask8 = type(uint8).max;
        uint8 upgradeAsUint;
        bytes32 upgradeSlot1;
        assembly {
            mstore(0, _upgradeId)
            mstore(32, upgradeToInfo.slot)
            let slot := keccak256(0, 64)

            upgradeSlot1 := sload(slot)
            // Get the upgradeType from the Upgrade struct by grabbing only the necessary 8 bits from the packed struct
            upgradeAsUint := and(shr(UPGRADE_UPGRADE_TYPE_BIT_OFFSET, upgradeSlot1), _mask8)
        }
        upgradeType_ = UpgradeType(upgradeAsUint);
    }

    function _getValidSkinIdForUpgrade(uint256 _upgradeId) internal view returns(uint32 validSkinId_){
        uint256 _mask32 = type(uint32).max;
        bytes32 upgradeSlot1;
        assembly {
            mstore(0, _upgradeId)
            mstore(32, upgradeToInfo.slot)
            let slot := keccak256(0, 64)

            upgradeSlot1 := sload(slot)
            validSkinId_ := and(shr(UPGRADE_VALID_SKIN_BIT_OFFSET, upgradeSlot1), _mask32)
        }
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolChopShopState_init() internal initializer {
        UtilitiesV2Upgradeable.__Utilities_init();
    }
}
