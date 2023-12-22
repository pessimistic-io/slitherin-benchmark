//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolChopShopInternal.sol";

/// @title Smol Chop Shop
/// @author Gearhart
/// @notice Store front for users to purchase and equip vehicle upgrades.

contract SmolChopShop is Initializable, SmolChopShopInternal {

    // -------------------------------------------------------------
    //                      Buy Upgrades
    // -------------------------------------------------------------

    // Unlock individual upgrade for single vehicle.
    /// @inheritdoc ISmolChopShop
    function buyUpgrade(
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external contractsAreSet whenNotPaused {
        _checkPurchaseType(_upgradeId);
        _buy(msg.sender, _vehicleAddress, _vehicleId, _upgradeId);
    }

    // Unlock individual upgrade for multiple vehicles or multiple upgrades for single vehicle. Can be any slot or even multiples of one slot type.
    /// @inheritdoc ISmolChopShop
    function buyUpgradeBatch(
        address[] calldata _vehicleAddress,
        uint256[] calldata _vehicleId,
        uint256[] calldata _upgradeId
    ) external contractsAreSet whenNotPaused {
        uint256 amount = _upgradeId.length;
        _checkLengths(amount, _vehicleId.length); 
        _checkLengths(amount, _vehicleAddress.length);
        for (uint256 i = 0; i < amount; i++) {
            _checkPurchaseType(_upgradeId[i]);
            _buy(msg.sender, _vehicleAddress[i], _vehicleId[i], _upgradeId[i]);
        }
    }

    // Unlcok upgrade that is gated by a merkle tree whitelist. Only unlockable with valid proof.
    /// @inheritdoc ISmolChopShop
    function buyExclusiveUpgrade(
        bytes32[] calldata _proof,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external contractsAreSet whenNotPaused {
        _checkPurchaseType(_upgradeId);
        if (userAllocationClaimed[msg.sender][_upgradeId]) revert WhitelistAllocationExceeded();
        userAllocationClaimed[msg.sender][_upgradeId] = true;
        _buyMerkle(msg.sender, _proof, _vehicleAddress, _vehicleId, _upgradeId, 0, 0);
    }

    // Unlock a limited offer upgrade for a specific sub group that is gated by a whitelist. One claim per address.
    /// @inheritdoc ISmolChopShop
    function specialEventClaim(
        bytes32[] calldata _proof,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external contractsAreSet whenNotPaused {
        (uint32 _limitedOfferId, uint32 _groupId) = _getLimitedOfferIdAndGroupForUpgrade(_upgradeId);
        if (_limitedOfferId == 0 || _groupId == 0) revert UpgradeNotPartOfSpecialEventClaim(_limitedOfferId, _groupId);
        if (userLimitedOfferAllocationClaimed[msg.sender][_limitedOfferId][_groupId] 
            || vehicleLimitedOfferAllocationClaimed[_vehicleAddress][_vehicleId][_limitedOfferId][_groupId])
        {
            revert AlreadyClaimedSpecialUpgradeFromThisGroup(msg.sender, _vehicleAddress, _vehicleId, _upgradeId);
        }
        userLimitedOfferAllocationClaimed[msg.sender][_limitedOfferId][_groupId] = true;
        vehicleLimitedOfferAllocationClaimed[_vehicleAddress][_vehicleId][_limitedOfferId][_groupId] = true;
        _buyMerkle(msg.sender, _proof, _vehicleAddress, _vehicleId, _upgradeId, _limitedOfferId, _groupId);
    }

    // Unlock a limited offer upgrade for a specific subgroup that is part of a global claim. One claim per vehicle.
    /// @inheritdoc ISmolChopShop
    function globalClaim(
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) external contractsAreSet whenNotPaused {
        (uint32 _limitedOfferId, uint32 _groupId) = _getLimitedOfferIdAndGroupForUpgrade(_upgradeId);
        if (_limitedOfferId != 0 || _groupId == 0) revert UpgradeNotAvailableForGlobalClaim(_limitedOfferId, _groupId);
        if (vehicleLimitedOfferAllocationClaimed[_vehicleAddress][_vehicleId][_limitedOfferId][_groupId]) {
            revert AlreadyClaimedFromThisGlobalDrop(_vehicleAddress, _vehicleId, _limitedOfferId, _groupId);
        }
        vehicleLimitedOfferAllocationClaimed[_vehicleAddress][_vehicleId][_limitedOfferId][_groupId] = true;
        _buy(msg.sender, _vehicleAddress, _vehicleId, _upgradeId);
    }

    // -------------------------------------------------------------
    //                   Equip/Unequip Upgrades
    // -------------------------------------------------------------

    // Equip sets of unlocked upgrades for vehicles. Or equip skin Id 0 to unequip all upgrades and return vehicle to initial state. Unequipped items are not lost.
    /// @inheritdoc ISmolChopShop
    function equipUpgrades(
        address[] calldata _vehicleAddress,
        uint256[] calldata _vehicleId,
        Vehicle[] calldata _upgradesToEquip
    ) external contractsAreSet whenNotPaused {
        uint256 amount = _vehicleId.length;
        _checkLengths(amount, _vehicleAddress.length);
        _checkLengths(amount, _upgradesToEquip.length);
        for (uint256 i = 0; i < amount; i++) {
            _equip(msg.sender, _vehicleAddress[i], _vehicleId[i], _upgradesToEquip[i]);
        }
    }

    // -------------------------------------------------------------
    //                     Exchange Trophies
    // -------------------------------------------------------------

    // Burns amount of each trophy in exchange for equal value in Coconuts. Coconuts are only used to buy vehicle upgrades and exchange for magic emissions. 
    // One way exchange. No converting back to racingTrophies from Coconuts.
    /// @inheritdoc ISmolChopShop
    function exchangeTrophiesBatch(
        uint256[] calldata _trophyIds, 
        uint256[] calldata _amountsToBurn
    ) external contractsAreSet whenNotPaused {
        uint256 length = _trophyIds.length;
        uint256 amountToReceive;
        _checkLengths(length, _amountsToBurn.length);
        for (uint256 i = 0; i < length; i++) {
            if (trophyExchangeValue[_trophyIds[i]] == 0) revert TrophyExchangeValueNotSet();
            _checkTrophyBalance(msg.sender, _trophyIds[i], _amountsToBurn[i]);
            amountToReceive += _amountsToBurn[i] * trophyExchangeValue[_trophyIds[i]];
        }
        require (amountToReceive > 0);
        racingTrophies.burnBatch(msg.sender, _trophyIds, _amountsToBurn);
        racingTrophies.mint(msg.sender, coconutId, amountToReceive);
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function initialize() external initializer {
        SmolChopShopInternal.__SmolChopShopInternal_init();
    }
}
