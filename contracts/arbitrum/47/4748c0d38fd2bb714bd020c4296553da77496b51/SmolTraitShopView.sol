//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolTraitShopState.sol";

/// @title Smol Trait Shop View Functions
/// @author Gearhart
/// @notice External and internal view functions used by SmolTraitShop.

abstract contract SmolTraitShopView is Initializable, SmolTraitShopState {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //                  External View Functions
    // -------------------------------------------------------------

    /// @inheritdoc ISmolTraitShop
    function getTraitInfo(
        uint256 _traitId
    ) external view returns (Trait memory) {
        Trait memory trait = traitToInfo[_traitId];
        return trait;
    }

    /// @inheritdoc ISmolTraitShop
    function getTraitsOwnedBySmol(
        uint256 _smolId
    ) external view returns (uint256[] memory) {
        return traitIdsOwnedBySmol[_smolId].values();
    }

    /// @inheritdoc ISmolTraitShop
    function getTraitOwnershipBySmol( 
        uint256 _smolId,
        uint256 _traitId
    ) public view returns (bool isOwnedBySmol_) {
        isOwnedBySmol_ = traitIdsOwnedBySmol[_smolId].contains(_traitId);
    }

    /// @inheritdoc ISmolTraitShop
    function getTraitsForSale(
        TraitType _traitType
    ) external view returns (uint256[] memory traitTypeForSale_) {
        uint256 forSaleAllLength = traitIdsForSale.length();
        uint256 countForSaleByTrait;
        for (uint256 i = 0; i < forSaleAllLength; i++) {
            if(!_isTraitInType(_traitType, traitIdsForSale.at(i))) {
                continue;
            }
            countForSaleByTrait++;
        }
        traitTypeForSale_ = new uint256[](countForSaleByTrait);
        uint256 traitCountCur;
        for (uint256 i = 0; i < forSaleAllLength; i++) {
            if(!_isTraitInType(_traitType, traitIdsForSale.at(i))) {
                continue;
            }
            traitTypeForSale_[traitCountCur++] = traitIdsForSale.at(i);
        }
    }

    /// @inheritdoc ISmolTraitShop
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
            _checkIqBalance(_smolId, price_);
        }
    }

    /// @dev Verify user is owner of smol.
    function _checkSmolOwnership(
        address _userAddress,
        uint256 _smolId
    ) internal view {
        if (smolBrains.ownerOf(_smolId) != _userAddress) revert MustBeOwnerOfSmol();
    }

    /// @dev Check IQ balance of selected Smol Brain.
    function _checkIqBalance(
        uint256 _smolId,
        uint256 _amount
    ) internal view {
        TokenDetails memory details = smolSchool.tokenDetails(address(smolBrains), 0, _smolId);
        uint256 iq = uint256(details.statAccrued);
        if (iq < _amount) revert InsufficientBalance(iq, _amount);
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

    /// @dev If the id is in a trait type that is not what we are looking for return false
    // ex: _traitType == _traitType.Clothes, skip when the id is < the first id in Clothes (1 * TRAIT_TYPE_OFFSET) or >= TraitType.Glasses
    function _isTraitInType(TraitType _traitType, uint256 _traitId) internal pure returns(bool isInType_) {
        uint256 nextTraitTypeOffset = (uint256(_traitType) + 1) * TRAIT_TYPE_OFFSET;
        // The value of the current trait type offset for id 1
        uint256 thisTraitTypeOffset = (uint256(_traitType)) * TRAIT_TYPE_OFFSET;
        isInType_ = _traitId < nextTraitTypeOffset && _traitId >= thisTraitTypeOffset;
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
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolTraitShopView_init() internal initializer {
        SmolTraitShopState.__SmolTraitShopState_init();
    }
}
