// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Smol Chop Shop Interface
/// @author Gearhart
/// @notice Interface and custom errors for SmolChopShop. 

interface ISmolChopShop {

    // -------------------------------------------------------------
    //                     Custom Errors
    // -------------------------------------------------------------
    
    error ContractsAreNotSet();
    error ArrayLengthMismatch();
    error TrophyExchangeValueNotSet();
    error CoconutIdNotSet();
    error InsufficientTrophies(uint256 _balance, uint256 _price);
    error InvalidTrophyExchangeValue(uint256 _value);
    error InvalidUpgradeSupply();
    error UpgradeIdDoesNotExist(uint256 _upgradeId);
    error UpgradeIdSoldOut(uint256 _upgradeId);
    error UpgradeNotCurrentlyForSale(uint256 _upgradeId);
    error UpgradeNotCompatibleWithSelectedVehicle(VehicleType _vehicleType, VehicleType _expectedVehicleType);
    error UpgradeIsNotTradable();
    error MustBeOwnerOfVehicle();
    error ValidSkinIdMustBeOfTypeSkin(uint256 _validSkinId);
    error UpgradeAlreadyUnlockedForVehicle(address _vehicleAddress, uint256 _vehicleId, uint256 _upgradeId);
    error UpgradeNotUnlockedForVehicle(address _vehicleAddress, uint256 _vehicleId, uint256 _upgradeId);
    error UpgradeNotCompatibleWithSelectedSkin(uint256 _selectedSkinId, uint256 _validSkinId);
    error VehicleCanOnlyOwnOneSkin();
    error MustOwnASkinToUnlockOtherUpgrades();
    error MustOwnRequiredSkinToUnlockUpgrade(address _vehicleAddress, uint256 _vehicleId, uint256 _requiredUpgradeId);
    error UpgradeNotOfRequiredType(uint256 _upgradeId, UpgradeType _expectedUpgradeType);
    error UpgradeNotPartOfSpecialEventClaim(uint32 _limitedOfferId, uint32 subgroupId); 
    error UpgradeNotAvailableForGlobalClaim(uint32 _limitedOfferId, uint32 subgroupId);
    error MustCallBuyExclusiveUpgrade(uint256 _upgradeId);
    error MustCallSpecialEventClaim(uint256 _upgradeId);
    error MustCallGlobalClaim(uint256 _upgradeId);
    error MerkleRootNotSet();
    error InvalidMerkleProof();
    error WhitelistAllocationExceeded();
    error InvalidLimitedOfferId();
    error InvalidVehicleAddress(address _vehicleAddress);
    error AlreadyClaimedFromThisGlobalDrop(address _vehicleAddress, uint256 _vehicleId, uint256 _limitedOfferId, uint256 _groupId);
    error AlreadyClaimedSpecialUpgradeFromThisGroup(address _user, address _vehicleAddress, uint256 _vehicleId, uint256 _upgradeId);

    // -------------------------------------------------------------
    //                      External Functions
    // -------------------------------------------------------------

    /// @notice Unlock individual upgrade for one vehicle.
    /// @dev Will revert if either limitedOfferId or subgroupId are > 0 for selected upgrade.
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of selected vehicle token.
    /// @param _upgradeId Id number of specifiic upgrade.
    function buyUpgrade(
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external;

    /// @notice Unlock individual upgrade for multiple vehicles or multiple upgrades for single vehicle. Can be any slot or even multiples of one slot type. 
    /// @dev Will revert if either limitedOfferId or subgroupId are > 0 for selected upgrade.
    /// @param _vehicleAddress Array of addresses for collections that vehicle tokens are from.
    /// @param _vehicleId Array of id numbers for selected vehicle tokens.
    /// @param _upgradeId Array of id numbers for selected upgrades.
    function buyUpgradeBatch(
        address[] calldata _vehicleAddress,
        uint256[] calldata _vehicleId,
        uint256[] calldata _upgradeId
    ) external;

    /// @notice Unlock upgrade that is gated by a merkle tree whitelist. Only unlockable with valid proof.
    /// @dev Will revert if either limitedOfferId or subgroupId are > 0 for selected upgrade.
    /// @param _proof Merkle proof to be checked against stored merkle root.
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of selected vehicle token.
    /// @param _upgradeId Id number of specifiic upgrade.
    function buyExclusiveUpgrade(
        bytes32[] calldata _proof,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external;

    /// @notice Unlock a limited offer upgrade for a specific limited offer subgroup that is gated by a whitelist. Only unlockable with valid Merkle proof.
    /// @dev Will revert if upgrade has no Merkle root set, if upgrade is not apart of a limitedOfferId > 0 with valid subgroup, or if user has claimed any other upgrade from the same subgroup.
    /// @param _proof Merkle proof to be checked against stored Merkle root.
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of selected vehicle token.
    /// @param _upgradeId Id number of specifiic upgrade.
    function specialEventClaim(
        bytes32[] calldata _proof,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external;

    /// @notice Unlock a limited offer upgrade for a specific limited offer group that is part of a global claim. One claim per vehicle.
    /// @dev Will revert if upgrade has no Merkle root set, if upgrade is not apart of a limitedOfferId = 0 with valid subgroup, or if user has claimed any other upgrade from the same subgroup.
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of selected vehicle token.
    /// @param _upgradeId Id number of specifiic upgrade.
    function globalClaim(
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external;

    /// @notice Equip sets of unlocked upgrades for vehicles. Or equip skin Id 0 to unequip all upgrades and return vehicle to initial state. Unequipped items are not lost.
    /// @param _vehicleAddress Array of addresses for collections that vehicle tokens are from.
    /// @param _vehicleId Array of id numbers for selected vehicle tokens.
    /// @param _upgradesToEquip Array of Vehicle structs with upgrade ids to be equipped to each vehicle.
    function equipUpgrades(
        address[] calldata _vehicleAddress,
        uint256[] calldata _vehicleId,
        Vehicle[] calldata _upgradesToEquip
    ) external;

    /// @notice Burns amount of trophies in exchange for equal value in Coconuts. One way exchange. No converting back to racingTrophies from Coconuts. Coconuts are only used to buy vehicle upgrades and exchange for Magic emissions. 
    /// @param _trophyIds Token Ids of trophy nfts to be burned.
    /// @param _amountsToBurn Amounts of each trophy id to be exchanged at current rate.
    function exchangeTrophiesBatch(
        uint256[] calldata _trophyIds, 
        uint256[] calldata _amountsToBurn
    ) external;

    // -------------------------------------------------------------
    //                      View Functions
    // -------------------------------------------------------------

    /// @notice Get currently equipped upgrades for a vehicle. 
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of vehicle token.
    /// @return equippedUpgrades_ Vehicle struct containing ids of equipped Upgrades for a given vehicle.
    function getEquippedUpgrades(
        address _vehicleAddress,
        uint256 _vehicleId
    ) external view returns (Vehicle memory equippedUpgrades_);

    /// @notice Get all upgrades unlocked for a vehicle.
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of vehicle token.
    /// @return unlockedUpgrades_ Array of all upgrade ids for a given type that have been unlocked for a vehicle.
    function getAllUnlockedUpgrades (
        address _vehicleAddress, 
        uint256 _vehicleId
    ) external view returns (uint256[] memory unlockedUpgrades_);

    /// @notice Check to see if a specific upgrade is unlocked for a given vehicle.
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of vehicle token.
    /// @param _upgradeId Id number of specifiic upgrade.
    /// @return isOwnedByVehicle_ Bool indicating if upgrade is owned (true) or not (false).
    function getUpgradeOwnershipByVehicle(
        address _vehicleAddress, 
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external view returns (bool isOwnedByVehicle_);

    /// @notice Check to see if a given vehicle has a skin unlocked.
    /// @param _vehicleAddress Address of collection that vehicle token is from.
    /// @param _vehicleId Id number of vehicle token.
    /// @return skinOwned_ Bool indicating if vehicle has unlocked a skin (true) or not (false).
    function skinOwnedByVehicle(
        address _vehicleAddress, 
        uint256 _vehicleId
    ) external view returns (bool skinOwned_);

    /// @notice Get all information about an upgrade by id.
    /// @param _upgradeId Id number of specifiic upgrade.
    /// @return Upgrade struct containing all information/metadata for a given upgrade Id. 
    function getUpgradeInfo ( 
        uint256 _upgradeId
    ) external view returns (Upgrade memory);

    /// @notice Check which id numbers of a specific upgrade type are currently for sale.
    /// @return upgradeTypeForSale_ Array of upgrade id numbers that can be bought/claimed for a specific upgrade type.
    function getUpgradesForSale(
        UpgradeType _upgradeType
    ) external view returns (uint256[] memory upgradeTypeForSale_);

    /// @notice Get upgrade ids that have been added to a specified subgroup for a given limited offer id.
    /// @dev All subgroups for each limitedOfferId > 0 represent seperate pools of upgrades available for a given special event. Each subgroup for limitedOfferId = 0 represents a seperate global claim.
    /// @param _limitedOfferId Number associated with the limitedOffer where trait subgroups were decided.
    /// @param _subgroupId Number associated with the subgroup array within limitedOfferId to be queried.
    /// @return subgroup_ Array of all upgrade ids for a given limitedOfferId and subgroupId.
    function getSubgroupFromLimitedOfferId(
        uint256 _limitedOfferId,
        uint256 _subgroupId
    ) external view returns(uint256[] memory subgroup_);

    /// @dev Returns base URI concatenated with upgrade ID + suffix.
    /// @param _upgradeId Id number of upgrade.
    /// @return uri_ Complete URI string for specific upgrade id. 
    function upgradeURI(
        uint256 _upgradeId
    ) external view returns (string memory uri_);

    /// @notice Verify necessary contract addresses have been set.
    function areContractsSet() external view returns(bool);

    // -------------------------------------------------------------
    //                      Admin Functions
    // -------------------------------------------------------------

    /// @notice Set new Upgrade struct info and save it to upgradeToInfo mapping.
    /// @dev Upgrade ids are auto incremented and assigned. Ids are unique to each upgrade type.
    /// @param _upgradeInfo Array of upgrade structs containing all information needed to add upgrade to contract.
    function setUpgradeInfo (
        CreateUpgradeArgs[] calldata _upgradeInfo
    ) external;

    /// @notice Edit Upgrade struct info and save it to upgradeToInfo mapping.
    /// @dev Cannot change UpgradeType after upgrade is added to contract.
    /// @param _upgradeId Array of upgrade ids to change info for.
    /// @param _newUpgradeInfo Array of upgrade structs containing all information to be saved to upgradeToInfo mapping.
    function changeUpgradeInfo(
        uint256[] calldata _upgradeId,
        CreateUpgradeArgs[] calldata _newUpgradeInfo
    ) external;

    /// @notice Set new base and suffix for URI to be concatenated with upgrade Id.
    /// @param _newBaseURI Portion of URI to come before upgrade Id + Suffix.
    /// @param _newSuffixURI Example suffix: ".json" for IPFS metadata or ".png" for IPFS images.
    function changeURI( 
        string calldata _newBaseURI,
        string calldata _newSuffixURI
    ) external;

    /// @notice Add limited offer upgrade ids to a subgroup within a limitedOfferId for specialEventClaim or globalClaim.
    /// @param _limitedOfferId Number of limited offer to set subgroups for. Must not be greater than latestLimitedOffer.
    /// @param _subgroupId Subgroup Id to differenciate between groups within limited offer id.
    /// @param _upgradeIds Array of id numbers to be added to a subgroup.
    function addUpgradeIdsToLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _upgradeIds
    ) external;

    /// @notice Remove limited offer upgrade ids from a subgroup within a limitedOfferId to remove id from specialEventClaim or globalClaim.
    /// @param _limitedOfferId Number of limited offer to edit subgroups for. Must not be greater than latestLimitedOffer.
    /// @param _subgroupId Subgroup Id to differenciate between groups within limited offer id.
    /// @param _upgradeIds Upgrade id numbers to be removed from a subgroup within a limitedOfferId.
    function removeUpgradeIdsFromLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _upgradeIds
    ) external;

    /// @notice Increment latestLimitedOfferId number by one to open up new subgroups for next special claim without erasing the last set.
    function incrementLimitedOfferId() external;

    /// @notice Set other trophy values in Coconuts for calculating exchange rate.
    /// @param _trophyId Array of trophy id numbers from the racing trophies contract.
    /// @param _trophyExchangeValue Array of trophy values (denominated in Coconuts) to be assigned to each given _trophyId.
    function setExchangeRates(
        uint256[] calldata _trophyId,
        uint256[] calldata _trophyExchangeValue
    ) external;

    /// @notice Set Id for 1155 token from racing trophy contract that will function as the chop shops payment currency.
    /// @dev Must be set to buy upgrades or exchange trophies.
    /// @param _coconutId Id number of Coconut NFT from the racing trophies contract.
    function setCoconutId(
        uint256 _coconutId
    ) external;

    /// @notice Set other contract addresses.
    function setContracts(
        address _smolCars,
        address _swolercycles,
        address _smolRacing,
        address _racingTrophies
    ) external;

    // -------------------------------------------------------------
    //                       Events
    // -------------------------------------------------------------

    /// @notice New upgrade has been unlocked for a vehicle.
    /// @param _vehicleAddress Address of collection that vehicle belongs to.
    /// @param _vehicleId Id number of vehicle that upgrade has been unlocked for.
    /// @param _upgradeId Id number of specifiic upgrade.
    /// @param _userAddress Address of vehicle owner.
    event UpgradeUnlocked(
        address indexed _vehicleAddress,
        uint256 indexed _vehicleId,
        uint256 indexed _upgradeId,
        address _userAddress
    );

    /// @notice New set of upgrades have been equipped to vehicle.
    /// @param _vehicleAddress Address of collection that vehicle belongs to.
    /// @param _vehicleId Id number of vehicle that upgrades have been applied to.
    /// @param _equippedUpgrades Vehicle struct that holds all currently equipped upgrades for a given vehicle.
    event UpgradesEquipped(
        address indexed _vehicleAddress,
        uint256 indexed _vehicleId,
        Vehicle _equippedUpgrades
    );

    /// @notice New upgrade has been added to contract.
    /// @param _upgradeId Id number of newly added upgrade.
    /// @param _upgradeInfo Upgrade struct holding all info/metadata for that upgrade.
    event UpgradeAddedToContract(
        uint256 indexed _upgradeId,
        Upgrade _upgradeInfo
    );

    /// @notice Upgrade has been added to or removed from sale.
    /// @dev forSale is a representation of if an item is currently claimable/buyable. It does not indicate if an upgrade is free or paid.
    /// @param _upgradeId Id number of upgrade that has been added/removed from sale.
    /// @param _added Bool indicating if an upgrade has been added to (true) or removed from (false) sale.
    event UpgradeSaleStateChanged(
        uint256 indexed _upgradeId,
        bool indexed _added
    );

    /// @notice Upgrade info has been changed
    /// @param _upgradeId Id number of upgrade that has had it's info/metadata changed.
    /// @param _upgradeInfo Upgrade struct holding all metadata for that upgrade.
    event UpgradeInfoChanged(
        uint256 indexed _upgradeId,
        Upgrade _upgradeInfo
    );

    // -------------------------------------------------------------
    //                       Enums
    // -------------------------------------------------------------

    // enum to control input, globaly unique id number generation, and upgrade application
    enum UpgradeType {
        Skin,
        Color,
        TopMod,
        FrontMod,
        SideMod,
        BackMod
    }

    // enum to control input and application by vehicle type
    enum VehicleType {
        Car,
        Cycle,
        Either
    }

    // -------------------------------------------------------------
    //                       Structs
    // -------------------------------------------------------------

    // struct for adding upgrades to contract to limit chance of admin error
    struct CreateUpgradeArgs {
        string name;
        uint32 price;
        uint32 maxSupply;
        uint32 limitedOfferId;                  // buy/buybatch = 0, exclusive = 0, specialEventClaim != 0, globalClaim = 0
        uint32 subgroupId;                      // buy/buybatch = 0, exclusive = 0, specialEventClaim != 0, globalClaim != 0
        bool forSale;
        bool tradable;
        UpgradeType upgradeType;
        uint32 validSkinId;
        VehicleType validVehicleType;
        bytes32 merkleRoot;
    }

    // struct to hold all relevant info needed for the purchase and application of upgrades
    // slot1:
    //    amountClaimed
    //    limitedOfferId
    //    maxSupply
    //    price
    //    subgroupId
    //    forSale
    //    tradable
    //    uncappedSupply
    //    upgradeType
    //    validSkinId
    //    validVehicleType
    //    {_gap} uint 24
    // slot2:
    //    name
    // slot3:
    //    uri
    // slot4:
    //    merkleRoot
    struct Upgrade {
        // ----- slot 1 -----
        uint32 amountClaimed;
        uint32 limitedOfferId;                  // buy/buybatch = 0, exclusive = 0, specialEventClaim != 0, globalClaim = 0
        uint32 maxSupply;
        uint32 price;
        uint32 subgroupId;                      // buy/buybatch = 0, exclusive = 0, specialEventClaim != 0, globalClaim != 0
        bool forSale;
        bool tradable;
        bool uncappedSupply;
        UpgradeType upgradeType;
        uint32 validSkinId;
        VehicleType validVehicleType;
        // ----- slot 2 -----
        string name;
        // ----- slot 3 -----
        string uri;
        // ----- slot 4 -----
        bytes32 merkleRoot;
    }

   // struct to act as inventory slots for attaching upgrades to vehicles
    struct Vehicle {
        uint32 skin;
        uint32 color;
        uint32 topMod;
        uint32 frontMod;
        uint32 sideMod;
        uint32 backMod;
    }
}
