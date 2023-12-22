//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolTraitShopAdmin.sol";

/// @title Smol Trait Shop View Functions
/// @author Gearhart
/// @notice External and internal view functions used by SmolTraitShop.

abstract contract SmolTraitShopView is Initializable, SmolTraitShopAdmin {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //                  External View Functions
    // -------------------------------------------------------------

    /// @notice Get SmolBrain struct with all currently equipped traits for selected smol.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @return SmolBrain struct with trait id numbers that have been equipped to a smol.
    function getEquippedTraits(
        uint256 _smolId
    ) external view returns (SmolBrain memory) {
        return smolToEquippedTraits[_smolId];
    }

    /// @notice Get all info for a specific trait.
    /// @param _traitId Id number of specifiic trait.
    /// @return Trait struct containing all info for a selected trait id.
    function getTraitInfo(
        uint256 _traitId
    ) external view returns (Trait memory) {
        Trait memory trait = traitToInfo[_traitId];
        trait.uri = traitURI(_traitId);
        return trait;
    }

    /// @notice Get all trait ids for a trait type that are currently owned by selected smol.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @return Array containing trait id numbers that have been unlocked for smol.
    function getTraitsOwnedBySmol(
        uint256 _smolId
    ) external view returns (uint256[] memory) {
        return traitIdsOwnedBySmol[_smolId].values();
    }

    /// @notice Check to see if a specific trait id is unlocked for a given smol.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specifiic trait.
    /// @return isOwnedBySmol_ Bool inicating if a trait is unlocked or not.
    function getTraitOwnershipBySmol( 
        uint256 _smolId,
        uint256 _traitId
    ) public view returns (bool isOwnedBySmol_) {
        isOwnedBySmol_ = traitIdsOwnedBySmol[_smolId].contains(_traitId);
    }

    /// @return traitTypeForSale_ containing trait id numbers that can be bought for that trait type.
    function getTraitsForSale(
        TraitType _traitType
    ) external view returns (uint256[] memory traitTypeForSale_) {
        uint256 forSaleAllLenth = traitIdsForSale.length();
        uint256 countForSaleByTrait;
        for (uint256 i = 0; i < forSaleAllLenth; i++) {
            if(!_isTraitInType(_traitType, traitIdsForSale.at(i))) {
                continue;
            }
            countForSaleByTrait++;
        }
        traitTypeForSale_ = new uint256[](countForSaleByTrait);
        uint256 traitCountCur;
        for (uint256 i = 0; i < forSaleAllLenth; i++) {
            if(!_isTraitInType(_traitType, traitIdsForSale.at(i))) {
                continue;
            }
            traitTypeForSale_[traitCountCur++] = traitIdsForSale.at(i);
        }
    }

    /// @notice Get trait ids that have been added to a specific subgroup for a given event number.
    /// @param _limitedOfferId Number associated with the event where trait subgroups were decided. (1 = smoloween)
    /// @param _subgroupId Subgroup within limitedOfferId to be returned
    function getSubgroupFromLimitedOfferId(
        uint256 _limitedOfferId,
        uint256 _subgroupId
    ) external view returns(uint256[] memory){
        return limitedOfferToGroupToIds[_limitedOfferId][_subgroupId].values();
    }

    // -------------------------------------------------------------
    //                  Internal View Functions
    // -------------------------------------------------------------

    /// @dev Various checks that must be made before any trait purchase.
    function _checkBeforePurchase(
        address _userAddress,
        uint256 _smolId,
        uint256 _traitId
    ) internal view returns(uint256 price_){
        _checkTraitId(_traitId);
        _checkSmolOwnership(_userAddress, _smolId);
        Trait memory trait = traitToInfo[_traitId];
        if (getTraitOwnershipBySmol(_smolId, _traitId)) revert TraitAlreadyUnlockedForSmol(_smolId, _traitId);
        if (!trait.forSale) revert TraitNotCurrentlyForSale(_traitId);
        if (!trait.uncappedSupply) {
            if (trait.amountClaimed + 1 > trait.maxSupply) revert TraitIdSoldOut(_traitId);
        }
        price_ = (uint256(trait.price) * 10**18);
        if (price_ != 0){
            _checkMagicBalance(_userAddress, price_);
        }
    }

    /// @dev Verify user is owner of smol.
    function _checkSmolOwnership(
        address _userAddress,
        uint256 _smolId
    ) internal view {
        if (smolBrains.ownerOf(_smolId) != _userAddress) revert MustBeOwnerOfSmol();
    }

    /// @dev Check balance of magic for user.
    function _checkMagicBalance(
        address _userAddress,
        uint256 _amount
    ) internal view {
        uint256 bal = magicToken.balanceOf(_userAddress);
        if (bal < _amount) revert InsufficientBalance(bal, _amount);
    }

    /// @dev Verify merkle proof for user and check if allocation has been claimed.
    function _checkWhitelistStatus(
        address _userAddress,
        bytes32[] calldata _proof,
        uint256 _traitId,
        uint256 _limitedOfferId,
        uint256 _groupId
    ) internal view {
        bytes32 leaf = keccak256(abi.encodePacked(_userAddress, _limitedOfferId, _groupId));
        if (!MerkleProofUpgradeable.verify(_proof, traitToInfo[_traitId].merkleRoot, leaf)) revert InvalidMerkleProof();
    }

    /// @dev Check used for ownership when equipping upgrades.
    function _checkBeforeEquip (
        uint256 _smolId,
        uint256 _traitId,
        TraitType _expectedTraitType
    ) internal view {
        if (_traitId != 0) {
            if (!getTraitOwnershipBySmol(_smolId, _traitId)) revert TraitNotUnlockedForSmol(_smolId, _traitId);
            if (!_isTraitInType(_expectedTraitType, _traitId)) revert TraitNotOfRequiredType(_traitId, _expectedTraitType);
        }
    }

    /// @dev Checking that buyTrait, buyTraitBatch, and buyExclusiveTrait purchases are going through the correct function for that trait.
    function _checkPurchaseType (
        uint256 _traitId
    ) internal view {
        (uint32 _limitedOfferId, uint32 _subgroupId) = _getLimitedOfferIdAndGroupForTrait(_traitId);
        if (_limitedOfferId != 0) revert MustCallSpecialEventClaim(_traitId);
        if (_subgroupId != 0) revert MustCallGlobalClaim(_traitId);
    }

    // If the id is in a trait type that is not what we are looking for return false
    // ex: _traitType == _traitType.Clothes, skip when the id is < the first id in Clothes (1 * TRAIT_TYPE_OFFSET) or >= TraitType.Glasses
    function _isTraitInType(TraitType _traitType, uint256 _traitId) internal pure returns(bool isInType_) {
        uint256 nextTraitTypeOffset = (uint256(_traitType) + 1) * TRAIT_TYPE_OFFSET;
        // The value of the current trait type offset for id 1
        uint256 thisTraitTypeOffset = (uint256(_traitType)) * TRAIT_TYPE_OFFSET;
        isInType_ = _traitId < nextTraitTypeOffset && _traitId >= thisTraitTypeOffset;
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolTraitShopView_init() internal initializer {
        SmolTraitShopAdmin.__SmolTraitShopAdmin_init();
    }
}
