//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolTraitShopInternal.sol";

/// @title Smol Trait Shop
/// @author Gearhart
/// @notice Store front for users to purchase and equip traits for Smol Brains.

contract SmolTraitShop is Initializable, SmolTraitShopInternal {

    // -------------------------------------------------------------
    //                      Buy Traits
    // -------------------------------------------------------------

    /// @notice Unlock individual trait for a Smol Brain.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specifiic trait.
    function buyTrait(
        uint256 _smolId,
        uint256 _traitId
    ) external contractsAreSet whenNotPaused {
        _checkPurchaseType(_traitId);
        _buy(msg.sender, _smolId, _traitId);
    }

    /// @notice Unlock individual trait for multiple Smols or multiple traits for single Smol. Can be any trait slot or even multiples of one trait type. 
    /// @param _smolIds Array of id numbers for selected Smol Brain tokens.
    /// @param _traitIds Array of id numbers for selected traits.
    function buyTraitBatch(
        uint256[] calldata _smolIds,
        uint256[] calldata _traitIds
    ) external contractsAreSet whenNotPaused {
        uint256 amount = _smolIds.length;
        _checkLengths(amount, _traitIds.length);
        for (uint256 i = 0; i < amount; i++) {
            _checkPurchaseType(_traitIds[i]);
            _buy(msg.sender, _smolIds[i], _traitIds[i]);
        }
    }

    /// @notice Unlock trait that is gated by a whitelist. Only unlockable with valid Merkle proof.
    /// @dev Will revert if trait has no Merkle root set or if trait is marked special.
    /// @param _proof Merkle proof to be checked against stored Merkle root.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specifiic trait.
    function buyExclusiveTrait(
        bytes32[] calldata _proof,
        uint256 _smolId,
        uint256 _traitId
    ) external contractsAreSet whenNotPaused {
        _checkPurchaseType(_traitId);
        if (userAllocationClaimed[msg.sender][_traitId]) revert WhitelistAllocationExceeded();
        userAllocationClaimed[msg.sender][_traitId] = true;
        _buyMerkle(msg.sender, _proof, _smolId, _traitId, 0, 0);
    }

    /// @notice Unlock a limited offer trait for a specific limited offer group that is gated by a whitelist. Only unlockable with valid Merkle proof.
    /// @dev Will revert if trait has no Merkle root set, if trait is not apart of a limited offer with valid subgroup, if user has claimed any other trait in the same tier.
    /// @param _proof Merkle proof to be checked against stored Merkle root.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specifiic trait.
    function specialEventClaim(
        bytes32[] calldata _proof,
        uint256 _smolId,
        uint256 _traitId
    ) external contractsAreSet whenNotPaused {
        (uint32 _limitedOfferId, uint32 _subgroupId) = _getLimitedOfferIdAndGroupForTrait(_traitId);
        if (_limitedOfferId == 0 || _subgroupId == 0) revert TraitNotPartOfSpecialEventClaim();
        if (userLimitedOfferAllocationClaimed[msg.sender][_limitedOfferId][_subgroupId] 
            || smolLimitedOfferAllocationClaimed[_smolId][_limitedOfferId][_subgroupId])
        {
            revert AlreadyClaimedSpecialTraitFromThisSubgroup(msg.sender, _smolId, _traitId);
        }
        userLimitedOfferAllocationClaimed[msg.sender][_limitedOfferId][_subgroupId] = true;
        smolLimitedOfferAllocationClaimed[_smolId][_limitedOfferId][_subgroupId] = true;
        _buyMerkle(msg.sender, _proof, _smolId, _traitId, _limitedOfferId, _subgroupId);
    }

    /// @notice Unlock a limited offer trait for a specific limited offer group that is part of a global claim. One claim per smol.
    /// @dev Will revert if trait has no Merkle root set, if trait is not apart of a limitedOfferId = 0 with valid subgroup, or if user has claimed any other trait from the same subgroup.
    /// @param _smolId Id number of selected Smol Brain token.
    /// @param _traitId Id number of specifiic trait.
    function globalClaim(
        uint256 _smolId,
        uint256 _traitId
    ) external contractsAreSet whenNotPaused {
        (uint32 _limitedOfferId, uint32 _subgroupId) = _getLimitedOfferIdAndGroupForTrait(_traitId);
        if (_limitedOfferId != 0 || _subgroupId == 0) revert TraitNotAvailableForGlobalClaim(_limitedOfferId, _subgroupId);
        if (smolLimitedOfferAllocationClaimed[_smolId][_limitedOfferId][_subgroupId]) {
            revert AlreadyClaimedFromThisGlobalDrop(_smolId, _limitedOfferId, _subgroupId);
        }
        smolLimitedOfferAllocationClaimed[_smolId][_limitedOfferId][_subgroupId] = true;
        _buy(msg.sender, _smolId, _traitId);
    }

    // -------------------------------------------------------------
    //                      Equip / Remove Traits
    // -------------------------------------------------------------

    /// @notice Equip sets of unlocked traits for any number of Smol Brains in one tx.
    /// @param _smolId Array of id numbers for selected Smol Brain tokens.
    /// @param _traitsToEquip Array of SmolBrain structs with trait ids to be equipped to each smol.
    function equipTraits(
        uint256[] calldata _smolId,
        SmolBrain[] calldata _traitsToEquip
    ) external contractsAreSet whenNotPaused {
        uint256 amount = _smolId.length;
        _checkLengths(amount, _traitsToEquip.length);
        for (uint256 i = 0; i < amount; i++) {
            _equipSet(msg.sender, _smolId[i], _traitsToEquip[i]);
        }
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function initialize() external initializer {
        SmolTraitShopInternal.__SmolTraitShopInternal_init();
    }
}
