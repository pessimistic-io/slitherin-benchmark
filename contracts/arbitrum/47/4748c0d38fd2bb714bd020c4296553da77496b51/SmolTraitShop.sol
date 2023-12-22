//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolTraitShopInternal.sol";

/// @title Smol Trait Shop
/// @author Gearhart
/// @notice Store front for users to purchase and equip traits for Smol Brains.

contract SmolTraitShop is Initializable, SmolTraitShopInternal {

    // -------------------------------------------------------------
    //                     Buy / Claim Traits
    // -------------------------------------------------------------

    /// @inheritdoc ISmolTraitShop
    function buyTrait(
        uint256 _smolId,
        uint256 _traitId
    ) external contractsAreSet whenNotPaused {
        _checkPurchaseType(_traitId);
        _buy(msg.sender, _smolId, _traitId);
    }

    /// @inheritdoc ISmolTraitShop
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

    /// @inheritdoc ISmolTraitShop
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

    /// @inheritdoc ISmolTraitShop
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

    /// @inheritdoc ISmolTraitShop
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

    /// @inheritdoc ISmolTraitShop
    function equipTraits(
        uint256[] calldata _smolIds,
        SmolBrain[] calldata _traitsToEquip
    ) external contractsAreSet whenNotPaused {
        uint256 amount = _smolIds.length;
        _checkLengths(amount, _traitsToEquip.length);
        for (uint256 i = 0; i < amount; i++) {
            _equipSet(msg.sender, _smolIds[i], _traitsToEquip[i]);
        }
    }

    // -------------------------------------------------------------
    //                       Airdrop Traits
    // -------------------------------------------------------------

    /// @inheritdoc ISmolTraitShop
    function adminAirdrop(
        uint256[] calldata _smolIds,
        uint256[] calldata _traitIds
    ) external contractsAreSet whenNotPaused requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 amount = _smolIds.length;
        _checkLengths(amount, _traitIds.length);
        for (uint256 i = 0; i < amount; i++) {
            _airdrop(_smolIds[i], _traitIds[i]);
        }
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function initialize() external initializer {
        SmolTraitShopInternal.__SmolTraitShopInternal_init();
    }
}
