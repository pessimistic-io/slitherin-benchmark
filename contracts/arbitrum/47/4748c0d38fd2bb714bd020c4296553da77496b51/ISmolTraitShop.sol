// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Smol Trait Shop Interface
/// @author Gearhart
/// @notice Interface and custom errors for SmolTraitShop. 

interface ISmolTraitShop {

    // -------------------------------------------------------------
    //                     Custom Errors
    // -------------------------------------------------------------
    
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

    /// @notice Event for when a new Trait is added to a smols inventory.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specific trait.
    event TraitUnlocked(
        uint256 indexed _smolId,
        uint256 indexed _traitId
    );

    /// @notice Event for when a smol changes their equipped Traits.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _equippedTraits SmolBrain struct containing list of equipped traits for each slot.
    event UpdateSmolTraits(
        uint256 indexed _smolId,
        SmolBrain _equippedTraits
    );

    /// @notice Event for when a new Trait is added to the contract.
    /// @param _traitId Id number of newly added trait.
    /// @param _traitInfo Trait struct containing all info associated with specified trait.
    event TraitAddedToContract(
        uint256 indexed _traitId,
        Trait _traitInfo
    );

    /// @notice Trait info has been changed
    /// @param _traitId Id number of trait that has had it's info/metadata changed.
    /// @param _traitInfo Trait struct holding all info/metadata for that trait.
    event TraitInfoChanged(
        uint256 indexed _traitId,
        Trait _traitInfo
    );

    /// @notice Event for when a Trait has been added to or removed from sale.
    /// @param _traitId Id number of specific trait.
    /// @param _added Boolean indicating if that trait was added (true), or if it was removed (false).
    event TraitSaleStateChanged(
        uint256 indexed _traitId,
        bool _added
    );

    // -------------------------------------------------------------
    //                      External Functions
    // -------------------------------------------------------------

    /// @notice Unlock individual trait for a Smol Brain.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specific trait.
    function buyTrait(
        uint256 _smolId,
        uint256 _traitId
    ) external;

    /// @notice Unlock individual trait for multiple Smols or multiple traits for single Smol. Can be any trait type or even multiples of one trait type. 
    /// @param _smolIds Array of id numbers for selected Smol Brain tokens.
    /// @param _traitIds Array of id numbers for selected traits.
    function buyTraitBatch(
        uint256[] calldata _smolIds,
        uint256[] calldata _traitIds
    ) external;

    /// @notice Unlock trait that is gated by a whitelist. Only unlockable with valid Merkle proof.
    /// @dev Will revert if trait has no Merkle root set, if trait has limitedOfferId > 0, or if subgroupId > 0.
    /// @param _proof Merkle proof to be checked against stored Merkle root.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specific trait.
    function buyExclusiveTrait(
        bytes32[] calldata _proof,
        uint256 _smolId,
        uint256 _traitId
    ) external;

    /// @notice Unlock a limited offer trait for a specific limited offer group that is gated by a whitelist. Only unlockable with valid Merkle proof.
    /// @dev Will revert if trait has no Merkle root set, if limitedOfferId = 0, if subgroupId = 0, or if user has claimed any other trait in the same tier.
    /// @param _proof Merkle proof to be checked against stored Merkle root.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specific trait.
    function specialEventClaim(
        bytes32[] calldata _proof,
        uint256 _smolId,
        uint256 _traitId
    ) external;

    /// @notice Unlock a limited offer trait for a specific limited offer group that is part of a global claim. One claim per smol.
    /// @dev Will revert if trait has a non zero Merkle root, if limitedOfferId > 0, if subgroupId = 0, or if selected smol has claimed any other trait from the same subgroup.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specific trait.
    function globalClaim(
        uint256 _smolId,
        uint256 _traitId
    ) external;

    /// @notice Equip sets of unlocked traits for any number of Smol Brains in one tx.
    /// @param _smolId Array of id numbers for selected Smol Brain tokens.
    /// @param _traitsToEquip Array of SmolBrain structs with trait ids to be equipped to each smol.
    function equipTraits(
        uint256[] calldata _smolId,
        SmolBrain[] calldata _traitsToEquip
    ) external;

    // -------------------------------------------------------------
    //                      View Functions
    // -------------------------------------------------------------

    /// @notice Get all info for a specific trait.
    /// @param _traitId Id number of specific trait.
    /// @return Trait struct containing all info for a selected trait id.
    function getTraitInfo(
        uint256 _traitId
    ) external view returns (Trait memory);

    /// @notice Get all trait ids for a trait type that are currently owned by selected smol.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @return Array containing trait id numbers that have been unlocked for smol.
    function getTraitsOwnedBySmol(
        uint256 _smolId
    ) external view returns (uint256[] memory);

    /// @notice Check to see if a specific trait id is unlocked for a given smol.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specific trait.
    /// @return isOwnedBySmol_ Bool indicating if a trait is unlocked or not.
    function getTraitOwnershipBySmol( 
        uint256 _smolId,
        uint256 _traitId
    ) external view returns (bool isOwnedBySmol_);

    /// @notice Get all trait ids of a specific trait type(0-7) that are currently for sale / available for claim.
    /// @param _traitType Enum (0-7) that indicates which trait type to search for.
    /// @return traitTypeForSale_ Array containing trait id numbers that can currently be bought/claimed for that trait type.
    function getTraitsForSale(
        TraitType _traitType
    ) external view returns (uint256[] memory traitTypeForSale_);

    /// @notice Get trait ids that have been added to a specific subgroup for a given event number.
    /// @param _limitedOfferId Number associated with the event where trait subgroups were decided. (1 = smoloween)
    /// @param _subgroupId Subgroup within limitedOfferId to be returned
    function getSubgroupFromLimitedOfferId(
        uint256 _limitedOfferId,
        uint256 _subgroupId
    ) external view returns(uint256[] memory);

    // -------------------------------------------------------------
    //                      Admin Functions
    // -------------------------------------------------------------

    /// @notice Unlock items for given NFTs free of charge. Can only be called by admin. 
    /// @param _smolIds Array of nft ids that will be receiving the airdrop.
    /// @param _traitIds Array of item ids to be added to specified NFTs inventory.
    function adminAirdrop(
        uint256[] calldata _smolIds,
        uint256[] calldata _traitIds
    ) external;

    /// @notice Set new Trait struct info and save it to traitToInfo mapping. Leave URI as "" when setting trait info.
    /// @dev Price (in IQ points) should be input as whole numbers. Contract adds necessary zeros during purchase. (ex: 20 IQ => price = 20 NOT 20000000000000000000)
    /// @dev Trait ids are auto incremented and assigned. Ids are unique to each trait type.
    /// @param _traitInfo Array of Trait structs containing all information needed to add trait to contract.
    function setTraitInfo (
        CreateTraitArgs[] calldata _traitInfo
    ) external;

    /// @notice Edit Trait struct info and save it to traitToInfo mapping.
    /// @dev Cannot change TraitType or traitId after trait is added to contract.
    /// @param _traitId Array of trait ids to change info for.
    /// @param _newTraitInfo Array of Trait structs containing all information to be saved to traitToInfo mapping.
    function changeTraitInfo(
        uint256[] calldata _traitId,
        CreateTraitArgs[] calldata _newTraitInfo
    ) external;

    /// @notice Add special traits to a subgroup for specialEventClaim.
    /// @param _limitedOfferId Number of limited offer to set subgroups for. Must not be greater than latestLimitedOffer.
    /// @param _subgroupId Subgroup Id to differentiate between groups within limited offer id.
    /// @param _traitIds Array of id numbers to be added to subgroup.
    function addTraitsToLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _traitIds
    ) external;

    /// @notice Add special traits to a subgroup for specialEventClaim.
    /// @param _limitedOfferId Number of limited offer to set subgroups for. Must not be greater than latestLimitedOffer.
    /// @param _subgroupId Subgroup Id to differentiate between groups within limited offer id.
    /// @param _traitIds Array of id numbers to be removed from subgroup.
    function removeTraitsFromLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _traitIds
    ) external;

    /// @notice Increment latestLimitedOfferId number by one to open up new subgroups for next special claim without erasing the last set of tiers.
    function incrementLimitedOfferId() external;

    /// @notice Withdraw all Magic from contract to treasury.
    function withdrawMagic() external;

    /// @notice Set contract and wallet addresses.
    /// @param  _smolBrains Address of Smol Brains NFT proxy contract.
    /// @param _smolSchool Address of Smol Brains School proxy contract.
    /// @param _smolsState Address of proxy contract holding current smol state. Used for equipping traits.
    /// @param _magicToken Address of Magic token contract.
    /// @param _treasuryAddress Address of treasury wallet for magic withdrawals 
    function setContracts(
        address _smolBrains,
        address _smolSchool,
        address _smolsState,
        address _magicToken,
        address _treasuryAddress
    ) external;

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
    //    subgroupId
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
