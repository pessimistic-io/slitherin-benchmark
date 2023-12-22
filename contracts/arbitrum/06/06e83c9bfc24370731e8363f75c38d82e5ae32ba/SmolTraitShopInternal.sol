//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolTraitShopView.sol";

/// @title Smol Trait Shop Internal
/// @author Gearhart
/// @notice Internal functions used to purchase and equip traits for Smol Brains.

contract SmolTraitShopInternal is Initializable, SmolTraitShopView {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //                   Buy Internal Functions
    // -------------------------------------------------------------

    /// @dev Used by all buy functions except for traits that require merkle proof verification.
    function _buy(
        address _userAddress,
        uint256 _smolId,
        uint256 _traitId
    ) internal {
        if (traitToInfo[_traitId].merkleRoot != bytes32(0)) revert MustCallBuyExclusiveTrait(_traitId);
        uint256 price_ = _checkBeforePurchase(_userAddress, _smolId, _traitId);
        _unlockTrait(_userAddress, price_, _smolId, _traitId);
    }

    /// @dev Used for buy/claim functions that require merkle proof verification. 
    function _buyMerkle(
        address _userAddress,
        bytes32[] calldata _proof,
        uint256 _smolId,
        uint256 _traitId,
        uint256 _limitedOfferId,
        uint256 _groupId
    ) internal {
        if (traitToInfo[_traitId].merkleRoot == bytes32(0)) revert MerkleRootNotSet();
        _checkWhitelistStatus(_userAddress, _proof, _traitId, _limitedOfferId, _groupId);
        uint256 price_ = _checkBeforePurchase(_userAddress, _smolId, _traitId);
        _unlockTrait(_userAddress, price_, _smolId, _traitId);
    }

    /// @dev Internal helper function that unlocks an upgrade for specified vehicle and emits UpgradeUnlocked event.
    function _unlockTrait(
        address _userAddress,
        uint256 _price,
        uint256 _smolId,
        uint256 _traitId
    ) internal {
        if (_price != 0){
            magicToken.transferFrom(_userAddress, address(this), _price);
        }
        traitToInfo[_traitId].amountClaimed ++;
        // If item is sold out; remove that item from sale.
        if (traitToInfo[_traitId].amountClaimed == traitToInfo[_traitId].maxSupply) {
            _removeTraitFromSale(_traitId);
            traitToInfo[_traitId].forSale = false;
        }
        traitIdsOwnedBySmol[_smolId].add(_traitId);
        emit TraitUnlocked(
            _smolId,
            _traitId
        );
    } 

    // -------------------------------------------------------------
    //                  Equip Internal Functions
    // -------------------------------------------------------------

    /// @dev Equip a set of unlocked traits for single Smol Brain.
    function _equipSet(
        address _userAddress,
        uint256 _smolId,
        SmolBrain calldata _traitsToEquip
    ) internal {
        _checkSmolOwnership(_userAddress, _smolId);
        _checkBeforeEquip(_smolId, _traitsToEquip.background, TraitType.Background);
        _checkBeforeEquip(_smolId, _traitsToEquip.body, TraitType.Body);
        _checkBeforeEquip(_smolId, _traitsToEquip.hair, TraitType.Hair);
        _checkBeforeEquip(_smolId, _traitsToEquip.clothes, TraitType.Clothes);
        _checkBeforeEquip(_smolId, _traitsToEquip.glasses, TraitType.Glasses);
        _checkBeforeEquip(_smolId, _traitsToEquip.hat, TraitType.Hat);
        _checkBeforeEquip(_smolId, _traitsToEquip.mouth, TraitType.Mouth);
        _checkBeforeEquip(_smolId, _traitsToEquip.costume, TraitType.Costume);
        smolToEquippedTraits[_smolId] = _traitsToEquip;
        emit UpdateSmolTraits(
            _smolId, 
            _traitsToEquip
        );
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolTraitShopInternal_init() internal initializer {
        SmolTraitShopView.__SmolTraitShopView_init();
    }
}
