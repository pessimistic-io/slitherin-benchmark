// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Smol Trait Shop Interface
/// @author Gearhart
/// @notice Interface and custom errors for SmolTraitShop. 

interface ISmolTraitShop {
    
    error ContractsAreNotSet();
    error ArrayLengthMismatch();
    error InsufficientBalance(uint _balance, uint _price);
    error InvalidTraitSupply();
    error TraitIdDoesNotExist(uint _traitId);
    error TraitIdSoldOut(uint _traitId);
    error TraitNotCurrentlyForSale(uint _traitId);
    error MustBeOwnerOfSmol();
    error TraitAlreadyUnlockedForSmol(uint _smolId, uint _traitId);
    error TraitNotUnlockedForSmol(uint _smolId, uint _traitId);
    error MustCallBuyExclusiveTrait(uint _traitId);
    error TraitNotPartOfSpecialEventClaim();
    error TraitNotAvailableForGlobalClaim(uint _limitedOfferId, uint _subgroupId);
    error MerkleRootNotSet();
    error MustCallSpecialEventClaim(uint _traitId);
    error MustCallGlobalClaim(uint _traitId);
    error InvalidLimitedOfferId();
    error AlreadyClaimedFromThisGlobalDrop(uint _smolId, uint _limitedOfferId, uint _subgroupId);
    error AlreadyClaimedSpecialTraitFromThisSubgroup(address _userAddress, uint _smolId, uint _traitId);
    error InvalidMerkleProof();
    error WhitelistAllocationExceeded();
    error TraitIsNotTradable();
    error TraitNotOfRequiredType(uint256 _traitId, TraitType _expectedTraitType);

// -------------------------------------------------------------
//                       Events
// -------------------------------------------------------------

    // new Trait added to a smols inventory
    event TraitUnlocked(
        uint256 indexed _smolId,
        uint256 indexed _traitId
    );

    // new set of Traits equipped to smol
    event UpdateSmolTraits(
        uint256 indexed _smolId,
        SmolBrain _equippedTraits
    );

    // Trait has been added to contract
    event TraitAddedToContract(
        uint256 indexed _traitId,
        Trait _traitInfo
    );

    // Trait has been added to or removed from sale
    event TraitSaleStateChanged(
        uint256 indexed _traitId,
        bool _added
    );

// -------------------------------------------------------------
//                       Enums
// -------------------------------------------------------------

    // enum to control input and application
    // Because there are less than 255 values, this enum takes up uint8 storage capacity within a packable slot in a struct
    enum TraitType {
        Background,
        Body,
        Hair,
        Clothes,
        Glasses,
        Hat,
        Mouth,
        Costume
    }

// -------------------------------------------------------------
//                       Structs
// -------------------------------------------------------------

    // struct to hold all relevant info needed for the purchase and application of a trait
    struct CreateTraitArgs {
        string name;
        uint32 price;
        uint32 maxSupply;
        uint32 limitedOfferId;
        bool forSale;
        bool tradable;
        TraitType traitType;
        uint32 subgroupId;
        bytes32 merkleRoot;
    }

    // struct to hold all relevant info needed for the purchase and application of a trait
    // slot1:
    //    amountClaimed
    //    limitedOfferId
    //    maxSupply
    //    price
    //    forSale
    //    tradable
    //    uncappedSupply
    //    traitType
    //    {_gap} uint64
    // slot2:
    //    name
    // slot3:
    //    uri
    // slot4:
    //    merkleRoot
    struct Trait {
        // ----- slot 1 -----
        uint32 amountClaimed;
        // Whether or not this trait is associated to a Limited Offer
        uint32 limitedOfferId;
        uint32 maxSupply;
        uint32 price;
        bool forSale;
        bool tradable;
        bool uncappedSupply;
        TraitType traitType;
        uint32 subgroupId;
        // ----- slot 2 -----
        string name;
        // ----- slot 3 -----
        string uri;
        // ----- slot 4 -----
        // Whether or not a sale is allow listed vs open
        // This can encompass private sales as well as private claims (free sale)
        bytes32 merkleRoot;
    }
   
   // struct to act as inventory slots for equipping traits to smols
    struct SmolBrain {
        uint32 background;
        uint32 body;
        uint32 hair;
        uint32 clothes;
        uint32 glasses;
        uint32 hat;
        uint32 mouth;
        uint32 costume;
    }
}
