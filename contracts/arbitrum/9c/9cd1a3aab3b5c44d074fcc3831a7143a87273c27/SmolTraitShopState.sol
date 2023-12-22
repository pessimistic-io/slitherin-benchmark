//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleProofUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./IERC1155Upgradeable.sol";
import "./IERC721.sol";

import "./UtilitiesV2Upgradeable.sol";
import "./ISmolTraitShop.sol";

/// @title Smol Trait Shop State
/// @author Gearhart
/// @notice Shared storage layout for SmolTraitShop.

abstract contract SmolTraitShopState is Initializable, UtilitiesV2Upgradeable, ISmolTraitShop  {

// -------------------------------------------------------------
//                   Mappings & Variables
// -------------------------------------------------------------
    uint256 internal constant TRAIT_LIMITED_OFFER_ID_BIT_OFFSET = 32;
    uint256 internal constant TRAIT_TRAIT_TYPE_BIT_OFFSET = 152;
    uint256 internal constant TRAIT_TYPE_OFFSET = 1_000_000;
    uint256 internal constant TRAIT_GROUP_ID_BIT_OFFSET = 160;

    IERC721 public smolBrains;
    IERC20Upgradeable public magicToken;

    // team wallet address for magic withdraw
    address public treasuryAddress;

// -------------------------------------------------------------
//                   Merkle Verifications
// -------------------------------------------------------------

    // mapping for keeping track of user WL allocation if merkleroot is assigned to a trait
    // user address => trait Id => WL spot claimed or not
    mapping (address => mapping(uint256 => bool)) 
        public userAllocationClaimed;

    // mapping for keeping track of user WL allocation if merkleroot is assigned to a limited offer
    // user address => special event id => sub group => WL spot claimed or not
    mapping (address => mapping (uint256 => mapping(uint256 => bool)))
        public userLimitedOfferAllocationClaimed;

    // smol brain id => special event id => sub group => WL spot claimed or not
    mapping (uint256 => mapping (uint256 => mapping(uint256 => bool)))
        public smolLimitedOfferAllocationClaimed;
    
    // -------------------------------------------------------------
    //                   Limited Offers
    // -------------------------------------------------------------

    // event number => enum (TraitType) => tier of trait => ids of that type that are within that tier
    // Used to track the pool of available skins to choose from
    mapping (uint256 => mapping (uint256 => EnumerableSetUpgradeable.UintSet))
        internal limitedOfferToGroupToIds;

    // number for keeping track of current event and opening a new level of tiers (without erasing the last) for special claim (when incremented)
    // used when creating a new special event
    uint256 public latestLimitedOffer;

    // -------------------------------------------------------------
    //                   TraitType Metadata
    // -------------------------------------------------------------
    

    // base URI for a specific trait type to be concatenated with trait ID + suffix
    mapping (TraitType => string)
        public baseURI;
    // suffix URI for a specific trait type to be concatenated with base + trait ID
    mapping (TraitType => string)
        public suffixURI;
    // highest id number currently in use for each trait type
    mapping (TraitType => uint256) 
        public traitTypeToLastId;

    // -------------------------------------------------------------
    //                   Trait Metadata
    // -------------------------------------------------------------

    // mapping that holds struct containing trait info by trait type for each id
    // trait id => Trait struct 
    mapping (uint256 => Trait) 
        internal traitToInfo;

    // Set of all traits currently for sale
    EnumerableSetUpgradeable.UintSet internal traitIdsForSale;

    // -------------------------------------------------------------
    //                   SmolTrait Metadata
    // -------------------------------------------------------------

    // smol id => Enumerable Uint Set of all unlocked traits
    mapping (uint256 => EnumerableSetUpgradeable.UintSet)
        internal traitIdsOwnedBySmol;
    
    // mapping to struct holding ids of currently equiped traits for a given smol
    // smol id => SmolBrain struct
    mapping (uint256 => SmolBrain) 
        internal smolToEquippedTraits;

    // -------------------------------------------------------------
    //                         Internal
    // -------------------------------------------------------------

    /* solhint-disable no-inline-assembly */
    function _getLimitedOfferIdAndGroupForTrait(uint256 _traitId) internal view returns(uint32 limitedOfferId_, uint8 groupId_){
        uint256 _mask32 = type(uint32).max;
        uint256 _mask8 = type(uint8).max;
        assembly {
            mstore(0, _traitId)
            mstore(32, traitToInfo.slot)
            let slot := keccak256(0, 64)

            let traitSlot1 := sload(slot)
            // Get the limitedOfferId from the Trait struct by offsetting the first 32 bits (amountClaimed value)
            // And only getting the first 32 bits of that part of the slot (for limitedOfferId)
            // shr will delete the least significant 32 bits of the slot data, which is the value of Trait.amountClaimed
            // and with the full value of a 32 bit uint will only save the data from the remaining slot that overlaps
            //  the mask with the actual stored value
            limitedOfferId_ := and(shr(TRAIT_LIMITED_OFFER_ID_BIT_OFFSET, traitSlot1), _mask32)
            groupId_ := and(shr(TRAIT_GROUP_ID_BIT_OFFSET, traitSlot1), _mask8)
        }
    }

    function _getTypeForTrait(uint256 _traitId) internal view returns(TraitType traitType_){
        uint256 _mask8 = type(uint8).max;
        uint8 traitAsUint;
        bytes32 traitSlot1;
        assembly {
            mstore(0, _traitId)
            mstore(32, traitToInfo.slot)
            let slot := keccak256(0, 64)

            traitSlot1 := sload(slot)
            // Get the limitedOfferId from the Trait struct by offsetting the first 32 bits (amountClaimed value)
            // And only getting the first 32 bits of that part of the slot (for limitedOfferId)
            // shr will delete the least significant 32 bits of the slot data, which is the value of Trait.amountClaimed
            // and with the full value of a 32 bit uint will only save the data from the remaining slot that overlaps
            //  the mask with the actual stored value
            traitAsUint := and(shr(TRAIT_TRAIT_TYPE_BIT_OFFSET, traitSlot1), _mask8)
        }
        traitType_ = TraitType(traitAsUint);
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolTraitShopState_init() internal initializer {
        UtilitiesV2Upgradeable.__Utilities_init();
    }
}
