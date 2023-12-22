//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolChopShopAdmin.sol";

/// @title Smol Chop Shop Internal
/// @author Gearhart
/// @notice Internal functions used to purchase and equip vehicle upgrades.

abstract contract SmolChopShopInternal is Initializable, SmolChopShopAdmin {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //                   Buy Internal Functions
    // -------------------------------------------------------------

    /// @dev Used by all buy functions except for upgrades that require merkle proof verification.
    function _buy(
        address _userAddress,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) internal {
        if (upgradeToInfo[_upgradeId].merkleRoot != bytes32(0)) revert MustCallBuyExclusiveUpgrade(_upgradeId);
        uint256 price = _checkBeforePurchase(_userAddress, _vehicleAddress, _vehicleId, _upgradeId);
        _unlockUpgrade(_userAddress, price, _vehicleAddress, _vehicleId, _upgradeId);
    }

    /// @dev Used for buy/claim functions that require merkle proof verification. 
    function _buyMerkle(
        address _userAddress,
        bytes32[] calldata _proof,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId,
        uint256 _limitedOfferId,
        uint256 _groupId
    ) internal {
        if (upgradeToInfo[_upgradeId].merkleRoot == bytes32(0)) revert MerkleRootNotSet();
        _checkWhitelistStatus(_userAddress, _proof, _upgradeId, _limitedOfferId, _groupId);
        uint256 price_ = _checkBeforePurchase(_userAddress, _vehicleAddress, _vehicleId, _upgradeId);
        _unlockUpgrade(_userAddress, price_, _vehicleAddress, _vehicleId, _upgradeId);
    }

    /// @dev Internal helper function that unlocks an upgrade for specified vehicle and emits UpgradeUnlocked event.
    function _unlockUpgrade(
        address _userAddress,
        uint256 _price,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) internal {
        if (_price != 0){
            racingTrophies.burn(_userAddress, coconutId, _price);
        }
        upgradeToInfo[_upgradeId].amountClaimed ++;
        // If item is sold out; remove that item from sale.
        if (upgradeToInfo[_upgradeId].amountClaimed == upgradeToInfo[_upgradeId].maxSupply) {
            _removeUpgradeFromSale(_upgradeId);
            upgradeToInfo[_upgradeId].forSale = false;
        }
        upgradeIdsUnlockedForVehicle[_vehicleAddress][_vehicleId].add(_upgradeId);
        userToTotalAmountSpent[_userAddress] += _price;
        emit UpgradeUnlocked(
        _vehicleAddress,
        _vehicleId,
        _upgradeId,
        _userAddress
        );
    }

    // -------------------------------------------------------------
    //                  Equip Internal Functions
    // -------------------------------------------------------------
    
    /// @dev Equip a set of unlocked upgrades for single vehicle.
    function _equip(
        address _userAddress,
        address _vehicleAddress,
        uint256 _vehicleId,
        Vehicle calldata _upgradesToEquip
    ) internal {
        _checkVehicleOwnership(_userAddress, _vehicleAddress, _vehicleId);
        Vehicle memory vehicle;
        if (_upgradesToEquip.skin != 0) {
            _checkBeforeEquip(_vehicleAddress, _vehicleId, _upgradesToEquip.skin, 0, UpgradeType.Skin);
            _checkBeforeEquip(_vehicleAddress, _vehicleId, _upgradesToEquip.color, _upgradesToEquip.skin, UpgradeType.Color);
            _checkBeforeEquip(_vehicleAddress, _vehicleId, _upgradesToEquip.topMod, _upgradesToEquip.skin, UpgradeType.TopMod);
            _checkBeforeEquip(_vehicleAddress, _vehicleId, _upgradesToEquip.frontMod, _upgradesToEquip.skin, UpgradeType.FrontMod);
            _checkBeforeEquip(_vehicleAddress, _vehicleId, _upgradesToEquip.sideMod, _upgradesToEquip.skin, UpgradeType.SideMod);
            _checkBeforeEquip(_vehicleAddress, _vehicleId, _upgradesToEquip.backMod, _upgradesToEquip.skin, UpgradeType.BackMod);
            vehicle = _upgradesToEquip;
        }
        vehicleToEquippedUpgrades[_vehicleAddress][_vehicleId] = vehicle;
        emit UpgradesEquipped(
            _vehicleAddress,
            _vehicleId,
            vehicle
        );
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolChopShopInternal_init() internal initializer {
        SmolChopShopAdmin.__SmolChopShopAdmin_init();
    }
}
