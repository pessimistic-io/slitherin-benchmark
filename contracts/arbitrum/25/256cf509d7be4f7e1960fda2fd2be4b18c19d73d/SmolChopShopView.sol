//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolChopShopState.sol";

/// @title Smol Chop Shop View Functions
/// @author Gearhart
/// @notice External and internal view functions used by SmolChopShop.

abstract contract SmolChopShopView is Initializable, SmolChopShopState {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using StringsUpgradeable for uint256;

    // -------------------------------------------------------------
    //                    External View Functions
    // -------------------------------------------------------------

    // Get currently equipped upgrades for a vehicle. 
    /// @inheritdoc ISmolChopShop
    function getEquippedUpgrades(
        address _vehicleAddress,
        uint256 _vehicleId
    ) external view returns (Vehicle memory equippedUpgrades_) {
        equippedUpgrades_ = vehicleToEquippedUpgrades[_vehicleAddress][_vehicleId];
    }

    // Get all upgrades unlocked for a vehicle.
    /// @inheritdoc ISmolChopShop
    function getAllUnlockedUpgrades(
        address _vehicleAddress, 
        uint256 _vehicleId
    ) external view returns (uint256[] memory unlockedUpgrades_) {
        unlockedUpgrades_ = upgradeIdsUnlockedForVehicle[_vehicleAddress][_vehicleId].values();
    }

    // Check to see if a specific upgrade is unlocked for a given vehicle.
    /// @inheritdoc ISmolChopShop
    function getUpgradeOwnershipByVehicle(
        address _vehicleAddress, 
        uint256 _vehicleId,
        uint256 _upgradeId
    ) public view returns (bool isOwnedByVehicle_) {
        isOwnedByVehicle_ = upgradeIdsUnlockedForVehicle[_vehicleAddress][_vehicleId].contains(_upgradeId);
    }

    // Check to see if a given vehicle has a skin unlocked.
    /// @inheritdoc ISmolChopShop
    function skinOwnedByVehicle(
        address _vehicleAddress, 
        uint256 _vehicleId
    ) public view returns (bool skinOwned_) {
        uint256 length = upgradeIdsUnlockedForVehicle[_vehicleAddress][_vehicleId].length();
        for (uint256 i = 0; i < length; i++) {
            if (_isUpgradeInType(UpgradeType.Skin, upgradeIdsUnlockedForVehicle[_vehicleAddress][_vehicleId].at(i))) {
                return true;
            }
        }
        return false;
    }

    // Get all information about an upgrade by id.
    /// @inheritdoc ISmolChopShop
    function getUpgradeInfo( 
        uint256 _upgradeId
    ) external view returns (Upgrade memory) {
        Upgrade memory upgrade = upgradeToInfo[_upgradeId];
        upgrade.uri = upgradeURI(_upgradeId);
        return upgrade;
    }

    // Check which id numbers of a specific upgrade type are currently for sale.
    /// @inheritdoc ISmolChopShop
    function getUpgradesForSale(
        UpgradeType _upgradeType
    ) external view returns (uint256[] memory upgradeTypeForSale_) {
        uint256 forSaleAllLenth = upgradeIdsForSale.length();
        uint256 countForSaleByUpgrade;
        for (uint256 i = 0; i < forSaleAllLenth; i++) {
            if(!_isUpgradeInType(_upgradeType, upgradeIdsForSale.at(i))) {
                continue;
            }
            countForSaleByUpgrade++;
        }
        upgradeTypeForSale_ = new uint256[](countForSaleByUpgrade);
        uint256 upgradeCountCur;
        for (uint256 i = 0; i < forSaleAllLenth; i++) {
            if(!_isUpgradeInType(_upgradeType, upgradeIdsForSale.at(i))) {
                continue;
            }
            upgradeTypeForSale_[upgradeCountCur++] = upgradeIdsForSale.at(i);
        }
    }

    // Get upgrade ids that have been added to a specified subgroup for a given limited offer id.
    // All subgroups for each limitedOfferId > 0 represent seperate pools of upgrades available for a given special event.
    // Each subgroup for limitedOfferId = 0 represents a seperate global claim.
    /// @inheritdoc ISmolChopShop
    function getSubgroupFromLimitedOfferId(
        uint256 _limitedOfferId,
        uint256 _subgroupId
    ) external view returns(uint256[] memory subgroup_){
        subgroup_ = limitedOfferToGroupToIds[_limitedOfferId][_subgroupId].values();

    }

    // Get full URI for _upgradeId.
    /// @inheritdoc ISmolChopShop
    function upgradeURI(uint256 _upgradeId) public view returns (string memory uri_) {
        _checkUpgradeId(_upgradeId);
        string memory URI = baseURI;
        uri_ = bytes(URI).length > 0 ? string(abi.encodePacked(URI, _upgradeId.toString(), suffixURI)) : "";
    } 

    // -------------------------------------------------------------
    //                  Internal View Functions
    // -------------------------------------------------------------

    /// @dev Various checks that must be made before any upgrade purchase.
    function _checkBeforePurchase(
        address _userAddress,
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId
    ) internal view returns(uint256 price_){
        _checkUpgradeId(_upgradeId);
        _checkVehicleOwnership(_userAddress, _vehicleAddress, _vehicleId);
        Upgrade memory upgrade = upgradeToInfo[_upgradeId];
        if (getUpgradeOwnershipByVehicle(_vehicleAddress, _vehicleId, _upgradeId)) 
        {
            revert UpgradeAlreadyUnlockedForVehicle(_vehicleAddress, _vehicleId, _upgradeId);
        }
        if (!upgrade.forSale) revert UpgradeNotCurrentlyForSale(_upgradeId);
        if (!upgrade.uncappedSupply) {
            if (upgrade.amountClaimed + 1 > upgrade.maxSupply) revert UpgradeIdSoldOut(_upgradeId);
        }
        if (upgrade.upgradeType == UpgradeType.Skin) {
            if (skinOwnedByVehicle(_vehicleAddress, _vehicleId)) {
                revert VehicleCanOnlyOwnOneSkin();
            }
        }
        if (upgrade.upgradeType != UpgradeType.Skin) {
            if (!skinOwnedByVehicle(_vehicleAddress, _vehicleId)) {
                revert MustOwnASkinToUnlockOtherUpgrades();
            }
            uint32 requiredSkinId = upgrade.validSkinId;
            if (requiredSkinId != 0 && !getUpgradeOwnershipByVehicle(_vehicleAddress, _vehicleId, requiredSkinId))
            {
                revert MustOwnRequiredSkinToUnlockUpgrade(_vehicleAddress, _vehicleId, requiredSkinId);
            }
        }
        _checkCompatibility(_vehicleAddress, upgrade.validVehicleType);
        price_ = upgrade.price;
        if (price_ != 0){
            _checkTrophyBalance(_userAddress, coconutId, price_);
        }
    }

    /// @dev Verify _userAddress is vehicle owner and throw if _vehicleAddress is neither car nor cycle.
    function _checkVehicleOwnership(
        address _userAddress,
        address _vehicleAddress,
        uint256 _vehicleId
    ) internal view {
        if (_vehicleAddress == address(smolCars)){
            if (smolCars.ownerOf(_vehicleId) != _userAddress 
                && !smolRacing.ownsVehicle(_vehicleAddress, _userAddress, _vehicleId)) 
            {
                revert MustBeOwnerOfVehicle();
            }
        }
        else if (_vehicleAddress == address(swolercycles)){
            if (swolercycles.ownerOf(_vehicleId) != _userAddress 
                && !smolRacing.ownsVehicle(_vehicleAddress, _userAddress, _vehicleId)) 
            {
                revert MustBeOwnerOfVehicle();
            }
        }
        else{
            revert InvalidVehicleAddress(_vehicleAddress);
        }
    }

    /// @dev Verify upgrade is compatible with selected vehicle and throw if _vehicleAddress is neither car nor cycle.
    function _checkCompatibility(
        address _vehicleAddress,
        VehicleType _validVehicleType
    ) internal view {
        if (_vehicleAddress == address(smolCars)){
            if (_validVehicleType == VehicleType.Cycle) revert UpgradeNotCompatibleWithSelectedVehicle(VehicleType.Car, _validVehicleType);
        }
        else if (_vehicleAddress == address(swolercycles)){
            if (_validVehicleType == VehicleType.Car) revert UpgradeNotCompatibleWithSelectedVehicle(VehicleType.Cycle, _validVehicleType);
        }
        else{
            revert InvalidVehicleAddress(_vehicleAddress);
        }
    }

    /// @dev Check balance of trophyId for _userAddress.
    function _checkTrophyBalance(
        address _userAddress,
        uint256 _trophyId,
        uint256 _amount
    ) internal view {
        if (coconutId == 0) revert CoconutIdNotSet();
        uint256 bal = racingTrophies.balanceOf(_userAddress, _trophyId);
        if (bal < _amount) revert InsufficientTrophies(bal, _amount);
    }

    /// @dev Verify merkle proof for user.
    function _checkWhitelistStatus(
        address _userAddress,
        bytes32[] calldata _proof,
        uint256 _upgradeId,
        uint256 _limitedOfferId,
        uint256 _groupId
    ) internal view {
        bytes32 leaf = keccak256(abi.encodePacked(_userAddress, _limitedOfferId, _groupId));
        if (!MerkleProofUpgradeable.verify(_proof, upgradeToInfo[_upgradeId].merkleRoot, leaf)) revert InvalidMerkleProof();
    }

    /// @dev Check used for ownership and validity when equipping upgrades.
    function _checkBeforeEquip (
        address _vehicleAddress,
        uint256 _vehicleId,
        uint256 _upgradeId,
        uint256 _skinId,
        UpgradeType _expectedUpgradeType
    ) internal view {
        if (_upgradeId != 0) {
            _checkCompatibility(_vehicleAddress, upgradeToInfo[_upgradeId].validVehicleType);
            if (!getUpgradeOwnershipByVehicle(_vehicleAddress, _vehicleId, _upgradeId)) 
            {
                revert UpgradeNotUnlockedForVehicle(_vehicleAddress, _vehicleId, _upgradeId);
            }
            if (!_isUpgradeInType(_expectedUpgradeType, _upgradeId)) revert UpgradeNotOfRequiredType(_upgradeId, _expectedUpgradeType);
            if (_skinId != 0){
                uint256 validSkinId = _getValidSkinIdForUpgrade(_upgradeId);
                if (validSkinId != 0 && validSkinId != _skinId) revert UpgradeNotCompatibleWithSelectedSkin(_skinId, validSkinId);
            }
        }
    }

    /// @dev Checking that buyUpgrade, buyUpgradeBatch, and buyExclusiveUpgrade purchases are going through the correct function for that upgrade.
    function _checkPurchaseType (
        uint256 _upgradeId
    ) internal view {
        (uint32 _limitedOfferId, uint32 _groupId) = _getLimitedOfferIdAndGroupForUpgrade(_upgradeId);
        if (_limitedOfferId != 0) revert MustCallSpecialEventClaim(_upgradeId);
        if (_groupId != 0) revert MustCallGlobalClaim(_upgradeId);
    }

    /// @dev Check to verify array lengths of input arrays are equal
    function _checkLengths(
        uint256 target,
        uint256 length
    ) internal pure {
        if (target != length) revert ArrayLengthMismatch();
    }

    /// @dev Check to verify _upgradeId is within range of valid upgrade ids.
    function _checkUpgradeId (
        uint256 _upgradeId
    ) internal view{
        UpgradeType _upgradeType = _getTypeForUpgrade(_upgradeId);
        if (_upgradeId <= 0 
            || upgradeTypeToLastId[_upgradeType] < _upgradeId - (uint256(_upgradeType) * UPGRADE_TYPE_OFFSET)) 
        {
            revert UpgradeIdDoesNotExist(_upgradeId);
        }
    }

    /// @dev  If the id is in a upgrade type that is not what we are looking for return false
    // ex: _upgradeType == _upgradeType.Color, skip when the id is < the first id in Colors (1 * UPGRADE_TYPE_OFFSET) or >= UpgradeType.TopMod
    function _isUpgradeInType(UpgradeType _upgradeType, uint256 _upgradeId) internal pure returns(bool isInType_) {
        uint256 nextUpgradeTypeOffset = (uint256(_upgradeType) + 1) * UPGRADE_TYPE_OFFSET;
        // The value of the current upgrade type offset for id 1
        uint256 thisUpgradeTypeOffset = (uint256(_upgradeType)) * UPGRADE_TYPE_OFFSET;
        isInType_ = _upgradeId < nextUpgradeTypeOffset && _upgradeId >= thisUpgradeTypeOffset;
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolChopShopView_init() internal initializer {
        SmolChopShopState.__SmolChopShopState_init();
    }
}
