//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolTraitShopState.sol";

/// @title Smol Trait Shop Admin Controls
/// @author Gearhart
/// @notice Admin control functions for SmolTraitShop.

abstract contract SmolTraitShopAdmin is Initializable, SmolTraitShopState {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using StringsUpgradeable for uint256;

// -------------------------------------------------------------
//               External Admin/Owner Functions
// -------------------------------------------------------------

    /// @notice Set new Trait struct info and save it to traitToInfo mapping. Leave URI as "" when setting trait info.
    ///  Price should be input as whole numbers, decimals are added during purchase. (ex: 200 magic => price = 200 NOT 200000000000000000000)
    /// @dev Trait ids are auto incremented and assigned. Ids are unique to each trait type.
    /// @param _traitInfo Array of Trait structs containing all information needed to add trait to contract.
    function setTraitInfo (
        CreateTraitArgs[] calldata _traitInfo
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 amount = _traitInfo.length;
        for (uint256 i = 0; i < amount; i++) {
            TraitType traitType = _traitInfo[i].traitType;
            Trait memory trait = Trait({
                name: _traitInfo[i].name,
                price: _traitInfo[i].price,
                maxSupply: _traitInfo[i].maxSupply,
                limitedOfferId: _traitInfo[i].limitedOfferId,
                forSale: _traitInfo[i].forSale,
                tradable: _traitInfo[i].tradable,
                traitType: _traitInfo[i].traitType,
                subgroupId: _traitInfo[i].subgroupId,
                merkleRoot: _traitInfo[i].merkleRoot,
                amountClaimed: 0,
                uncappedSupply: _traitInfo[i].maxSupply == 0,
                uri: ""
            });
            // gas optimization on sread ops
            uint256 traitTypeId = traitTypeToLastId[traitType] + 1;
            uint256 id = traitTypeId + (uint256(traitType) * TRAIT_TYPE_OFFSET);
            traitTypeToLastId[traitType] = traitTypeId;
            traitToInfo[id] = trait;
            // add concatenated URI to trait for event emission but do not save to storage
            trait.uri = traitURI(id);
            emit TraitAddedToContract(
                id, 
                trait
            );
            // Keep after TraitAddedToContract for clean event ordering
            //  TraitAddedToContract -> TraitAddedToSale
            if (trait.forSale){
                _addTraitToSale(id);
            }
        }
    }

    /// @notice Set new base URI to be concatenated with trait Id + suffix.
    /// @param _traitType Enum(0-7) representing which type of trait is being referenced.
    /// @param _newBaseURI Portion of URI to come before trait Id + Suffix. 
    function changeBaseURI(TraitType _traitType, string calldata _newBaseURI) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE){
        baseURI[_traitType] = _newBaseURI;
    }

    /// @notice Set new URI suffix to be added to the end of baseURI + trait Id.
    /// @param _traitType Enum(0-7) representing which type of trait is being referenced.
    /// @param _newSuffixURI Example suffix: ".json" for IPFS files
    function changeSuffixURI(TraitType _traitType, string calldata _newSuffixURI) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE){
        suffixURI[_traitType] = _newSuffixURI;
    }

    /// @notice Change existing trait sale status.
    /// @dev Also adds and removes trait from for sale array.
    /// @param _traitId Id number of specifiic trait.
    /// @param _forSale New bool value to add(true)/remove(false) traits from sale.
    function changeTraitSaleStatus (
        uint256 _traitId,
        bool _forSale
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        require (traitToInfo[_traitId].forSale != _forSale);
        _checkTraitId(_traitId);
        if (traitToInfo[_traitId].forSale && !_forSale){
            _removeTraitFromSale(_traitId);
            traitToInfo[_traitId].forSale = false;
        }
        else{
            _addTraitToSale(_traitId);
            traitToInfo[_traitId].forSale = true;
        }
    }

    /// @notice Change stored merkle root attached to existing trait for whitelist.
    /// @dev Change to 0x0000000000000000000000000000000000000000000000000000000000000000 to remove whitelist.
    /// @param _traitId Id number of specifiic trait.
    /// @param _merkleRoot New merkle root for whitelist verification or empty root for normal sale.
    function changeTraitMerkleRoot (
        uint256 _traitId,
        bytes32 _merkleRoot
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _checkTraitId(_traitId);
        traitToInfo[_traitId].merkleRoot = _merkleRoot;
    }

    /// @notice Change existing trait name.
    /// @param _traitId Id number of specifiic trait.
    /// @param _name New string to be set as trait name.
    function changeTraitName (
        uint256 _traitId,
        string calldata _name
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _checkTraitId(_traitId);
        traitToInfo[_traitId].name = _name;
    }

    /// @notice Change existing trait price.
    /// @param _traitId Id number of specifiic trait.
    /// @param _price New price for trait in base units.
    function changeTraitPrice (
        uint256 _traitId,
        uint32 _price
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _checkTraitId(_traitId);
        traitToInfo[_traitId].price = _price;
    }

    /// @notice Change max supply or remove supply cap for an existing trait. 
    /// @dev _maxSupply=0 : No supply cap | _maxSupply>0 : Supply cap is set to _maxSupply.
    /// @param _traitId Id number of specifiic trait.
    /// @param _maxSupply New max supply value for selected trait. Enter 0 to remove supply cap.
    function changeTraitSupply (
        uint256 _traitId,
        uint32 _maxSupply
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _checkTraitId(_traitId);
        if (_maxSupply != 0) {
            if (_maxSupply < traitToInfo[_traitId].amountClaimed) revert InvalidTraitSupply();
            traitToInfo[_traitId].maxSupply = _maxSupply;
            traitToInfo[_traitId].uncappedSupply = false;
        }
        else {
            traitToInfo[_traitId].maxSupply = 0;
            traitToInfo[_traitId].uncappedSupply = true;
        }
    }

    /// @notice Change existing trait limited offer id reference. Changing this value will affect claimability per grouping as well as exclusive vs special claims.
    /// @param _traitId Id number of specifiic trait.
    /// @param _limitedOfferId New number of limited offer to set subgroups for.
    /// @param _subgroupId Subgroup Id to differenciate between groups within limited offer id.
    function changeTraitSpecialStatus (
        uint256 _traitId,
        uint32 _limitedOfferId,
        uint8 _subgroupId
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        if (_limitedOfferId > latestLimitedOffer) revert InvalidLimitedOfferId();
        _checkTraitId(_traitId);
        traitToInfo[_traitId].limitedOfferId = _limitedOfferId;
        traitToInfo[_traitId].subgroupId = _subgroupId;
    }

    /// @notice Change existing trait tradable status. Set as true to allow a trait to be tokenized and transfered.
    /// @param _traitId Id number of specifiic trait.
    /// @param _tradable New tradable status for a specific trait.
    function changeTraitTradableStatus (
        uint256 _traitId,
        bool _tradable
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        _checkTraitId(_traitId);
        traitToInfo[_traitId].tradable = _tradable;
    }

    /// @notice Add special traits to a subgroup for specialEventClaim.
    /// @param _limitedOfferId Number of limited offer to set subgroups for. Must not be greater than latestLimitedOffer.
    /// @param _subgroupId Subgroup Id to differenciate between groups within limited offer id.
    /// @param _traitIds Array of id numbers to be added to subgroup.
    function addTraitsToLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _traitIds
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        if (_limitedOfferId > latestLimitedOffer) revert InvalidLimitedOfferId();
        uint256 length = _traitIds.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 id = _traitIds[i];
            _checkTraitId(id);
            limitedOfferToGroupToIds[_limitedOfferId][_subgroupId].add(id);
        }
    }

    /// @notice Add special traits to a subgroup for specialEventClaim.
    /// @param _limitedOfferId Number of limited offer to set subgroups for. Must not be greater than latestLimitedOffer.
    /// @param _subgroupId Subgroup Id to differenciate between groups within limited offer id.
    /// @param _traitIds Array of id numbers to be removed from subgroup.
    function removeTraitsFromLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _traitIds
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 length = _traitIds.length;
        for (uint256 i = 0; i < length; i++) {
            limitedOfferToGroupToIds[_limitedOfferId][_subgroupId].remove(_traitIds[i]);
        }
    }

    /// @notice Increment latestLimitedOfferId number by one to open up new subgroups for next special claim without erasing the last set of tiers.
    function incrementLimitedOfferId() external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE){
        latestLimitedOffer ++;
    }

    /// @notice Withdraw all Magic from contract.
    function withdrawMagic() external contractsAreSet requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 contractBalance = magicToken.balanceOf(address(this));
        magicToken.transfer(treasuryAddress, contractBalance);
    }

    /// @dev Returns base URI concatenated with trait ID + suffix.
    /// @param _traitId Id number of specifiic trait.
    /// @return URI string for trait id of trait type. 
    function traitURI(uint256 _traitId) public view returns (string memory) {
        _checkTraitId(_traitId);
        TraitType _traitType = _getTypeForTrait(_traitId);
        uint256 id = _traitId - (uint256(_traitType) * TRAIT_TYPE_OFFSET); 
        string memory URI = baseURI[_traitType];
        string memory suffix = suffixURI[_traitType];
        return bytes(URI).length > 0 ? string(abi.encodePacked(URI, id.toString(), suffix)) : "";
    } 

// -------------------------------------------------------------
//                   Internal Functions
// -------------------------------------------------------------

    /// @dev Adds trait id to sale array for that trait type.
    function _addTraitToSale (
        uint256 _traitId
    ) internal {
        traitIdsForSale.add(_traitId);
        emit TraitSaleStateChanged(
            _traitId, 
            true
        );
    }

    /// @dev Removes trait id from sale array for that trait type.
    function _removeTraitFromSale (
        uint256 _traitId
    ) internal {
        traitIdsForSale.remove(_traitId);
        emit TraitSaleStateChanged(
            _traitId, 
            false
        );
    }

    /// @dev Check to verify _traitId is within range of valid trait ids.
    function _checkTraitId (
        uint256 _traitId
    ) internal view {
        TraitType _traitType = _getTypeForTrait(_traitId);
        if (_traitId == 0 || traitTypeToLastId[_traitType] < _traitId - (uint256(_traitType) * TRAIT_TYPE_OFFSET)) revert TraitIdDoesNotExist(_traitId);
    }

    /// @dev Check to verify array lengths of input arrays are equal
    function _checkLengths(
        uint256 target,
        uint256 length
    ) internal pure {
        if (target != length) revert ArrayLengthMismatch();
    }

// -------------------------------------------------------------
//                 Essential Setter Functions
// -------------------------------------------------------------

    /// @notice Set contract and wallet addresses.
    function setContracts(
        address _smolBrains,
        address _magicToken,
        address _treasuryAddress
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        smolBrains = IERC721(_smolBrains);
        magicToken = IERC20Upgradeable(_magicToken);
        treasuryAddress = _treasuryAddress;
    }

// -------------------------------------------------------------
//                       Modifier
// -------------------------------------------------------------
    
    modifier contractsAreSet() {
        if(!areContractsSet()) revert ContractsAreNotSet();
        _;
    }

    /// @notice Verify necessary contract addresses have been set.
    function areContractsSet() public view returns(bool) {
        return address(smolBrains) != address(0)
        && address(magicToken) != address(0)
        && address(treasuryAddress) != address(0);
    }

// -------------------------------------------------------------
//                       Initializer
// -------------------------------------------------------------

    function __SmolTraitShopAdmin_init() internal initializer {
        SmolTraitShopState.__SmolTraitShopState_init();
    }
}
