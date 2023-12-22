//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolChopShopView.sol";

/// @title Smol Chop Shop Admin Controls
/// @author Gearhart
/// @notice Admin control functions for SmolChopShop.

abstract contract SmolChopShopAdmin is Initializable, SmolChopShopView {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //               External Admin/Owner Functions
    // -------------------------------------------------------------

    // Set new Upgrade struct info and save it to upgradeToInfo mapping.
    /// @inheritdoc ISmolChopShop
    function setUpgradeInfo (
        CreateUpgradeArgs[] calldata _upgradeInfo
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 amount = _upgradeInfo.length;
        for (uint256 i = 0; i < amount; i++) {
            UpgradeType upgradeType = _upgradeInfo[i].upgradeType;
            if (_upgradeInfo[i].validSkinId != 0) {
                _checkUpgradeId(_upgradeInfo[i].validSkinId);
                if (!_isUpgradeInType(UpgradeType.Skin, _upgradeInfo[i].validSkinId)) revert ValidSkinIdMustBeOfTypeSkin(_upgradeInfo[i].validSkinId);
            }
            Upgrade memory upgrade = Upgrade ({
                name: _upgradeInfo[i].name,
                price: _upgradeInfo[i].price,
                maxSupply: _upgradeInfo[i].maxSupply,
                limitedOfferId: _upgradeInfo[i].limitedOfferId,
                subgroupId: _upgradeInfo[i].subgroupId,
                forSale: _upgradeInfo[i].forSale,
                tradable: _upgradeInfo[i].tradable,
                upgradeType: _upgradeInfo[i].upgradeType,
                validSkinId: _upgradeInfo[i].validSkinId,
                validVehicleType: _upgradeInfo[i].validVehicleType,
                merkleRoot: _upgradeInfo[i].merkleRoot,
                amountClaimed: 0,
                uncappedSupply: _upgradeInfo[i].maxSupply == 0,
                uri: ""
            });
            // gas optimization on sread ops
            uint256 upgradeTypeId = upgradeTypeToLastId[upgradeType] + 1;
            uint256 id = upgradeTypeId + (uint256(upgradeType) * UPGRADE_TYPE_OFFSET);
            upgradeTypeToLastId[upgradeType] = upgradeTypeId;
            upgradeToInfo[id] = upgrade;
            // add concatenated URI to upgrade for event emission but do not need to save to storage
            upgrade.uri = upgradeURI(id);
            emit UpgradeAddedToContract(
                id, 
                upgrade
            );
            // Keep after UpgradeAddedToContract for clean event ordering
            //  UpgradeAddedToContract -> UpgradeAddedToSale
            if (upgrade.forSale){
                _addUpgradeToSale(id);
            }
        }
    }

    // Edit Upgrade struct info and save it to upgradeToInfo mapping.
    /// @inheritdoc ISmolChopShop
    function changeUpgradeInfo(
        uint256[] calldata _upgradeId,
        CreateUpgradeArgs[] calldata _newUpgradeInfo
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 amount = _upgradeId.length;
        _checkLengths(amount, _newUpgradeInfo.length);
        for (uint256 i = 0; i < amount; i++) {
            uint256 id = _upgradeId[i];
            _checkUpgradeId(id);
            CreateUpgradeArgs calldata _newInfo = _newUpgradeInfo[i];
            Upgrade memory upgrade = upgradeToInfo[id];
            if (_newInfo.validSkinId != 0) {
                _checkUpgradeId(_newInfo.validSkinId);
                if (!_isUpgradeInType(UpgradeType.Skin, _newInfo.validSkinId)) revert ValidSkinIdMustBeOfTypeSkin(_newInfo.validSkinId);
            }
            if (upgrade.maxSupply != _newInfo.maxSupply) {
                if (_newInfo.maxSupply != 0) {
                    if (_newInfo.maxSupply < upgrade.amountClaimed) revert InvalidUpgradeSupply();
                }
                upgrade.maxSupply = _newInfo.maxSupply;
                upgrade.uncappedSupply = _newInfo.maxSupply == 0;
            }
            if (upgrade.forSale != _newInfo.forSale){
                if (upgrade.forSale && !_newInfo.forSale){
                    _removeUpgradeFromSale(id);
                }
                else{
                    _addUpgradeToSale(id);
                }
                upgrade.forSale = _newInfo.forSale;
            }
            upgrade.name = _newInfo.name;
            upgrade.price = _newInfo.price;
            upgrade.limitedOfferId = _newInfo.limitedOfferId;
            upgrade.subgroupId = _newInfo.subgroupId;
            upgrade.tradable = _newInfo.tradable;
            upgrade.validSkinId = _newInfo.validSkinId;
            upgrade.validVehicleType = _newInfo.validVehicleType;
            upgrade.merkleRoot = _newInfo.merkleRoot;
            upgradeToInfo[id] = upgrade;
            // add concatenated URI to upgrade for event emission but do not save to storage
            upgrade.uri = upgradeURI(id);
            emit UpgradeInfoChanged(
                id,
                upgrade
            );
        }
    }

    // Set new base and suffix for URI to be concatenated with upgrade Id.
    /// @inheritdoc ISmolChopShop
    function changeURI(string calldata _newBaseURI, string calldata _newSuffixURI) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE){
        baseURI = _newBaseURI;
        suffixURI = _newSuffixURI;
    }

    // Add limited offer upgrade ids to a subgroup within a limitedOfferId for specialEventClaim or globalClaim.
    /// @inheritdoc ISmolChopShop
    function addUpgradeIdsToLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _upgradeIds
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        if (_limitedOfferId > latestLimitedOffer) revert InvalidLimitedOfferId();
        uint256 length = _upgradeIds.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 id = _upgradeIds[i];
            _checkUpgradeId(id);
            limitedOfferToGroupToIds[_limitedOfferId][_subgroupId].add(id);
        }
    }

    // Remove limited offer upgrade ids from a subgroup within a limitedOfferId to remove id from specialEventClaim or globalClaim.
    /// @inheritdoc ISmolChopShop
    function removeUpgradeIdsFromLimitedOfferGroup(
        uint256 _limitedOfferId,
        uint256 _subgroupId,
        uint256[] calldata _upgradeIds
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 length = _upgradeIds.length;
        for (uint256 i = 0; i < length; i++) {
            limitedOfferToGroupToIds[_limitedOfferId][_subgroupId].remove(_upgradeIds[i]);
        }
    }

    /// @inheritdoc ISmolChopShop
    function incrementLimitedOfferId() external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE){
        latestLimitedOffer ++;
    }

    // -------------------------------------------------------------
    //                   Internal Functions
    // -------------------------------------------------------------

    /// @dev Adds upgrade id to for sale array.
    function _addUpgradeToSale (
        uint256 _upgradeId
    ) internal {
        upgradeIdsForSale.add(_upgradeId);
        emit UpgradeSaleStateChanged(
            _upgradeId,
            true
        );
    }

    /// @dev Removes upgrade id from for sale array.
    function _removeUpgradeFromSale (
        uint256 _upgradeId
    ) internal {
        upgradeIdsForSale.remove(_upgradeId);
        emit UpgradeSaleStateChanged(
            _upgradeId,
            false
        );
    }

    // -------------------------------------------------------------
    //                 Essential Setter Functions
    // -------------------------------------------------------------

    // Set exchange rate for 1155 trophy ids from racing trophy contract denominated in Coconuts.
    /// @inheritdoc ISmolChopShop
    function setExchangeRates(
        uint256[] calldata _trophyId,
        uint256[] calldata _trophyExchangeValue
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 amount = _trophyId.length;
        _checkLengths(amount, _trophyExchangeValue.length);
        for(uint256 i = 0; i < amount; i++) {
            if (_trophyExchangeValue[i] == 0) revert InvalidTrophyExchangeValue(_trophyExchangeValue[i]);
            trophyExchangeValue[_trophyId[i]] = _trophyExchangeValue[i];
        }
    }

    // Set Id for 1155 token from racing trophy contract that will function as the chop shops payment currency.
    /// @inheritdoc ISmolChopShop
    function setCoconutId(
        uint256 _coconutId
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        coconutId = _coconutId;
    }

    // Set other contract addresses.
    /// @inheritdoc ISmolChopShop
    function setContracts(
        address _smolCars,
        address _swolercycles,
        address _smolRacing,
        address _racingTrophies
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        smolCars = IERC721(_smolCars);
        swolercycles = IERC721(_swolercycles);
        smolRacing = SmolRacing(_smolRacing);
        racingTrophies = ISmolRacingTrophies(_racingTrophies);
    }

    // -------------------------------------------------------------
    //                       Modifier
    // -------------------------------------------------------------
    
    modifier contractsAreSet() {
        if(!areContractsSet()) revert ContractsAreNotSet();
        _;
    }

    // Verify necessary contract addresses have been set.
    /// @inheritdoc ISmolChopShop
    function areContractsSet() public view returns(bool) {
        return address(smolCars) != address(0)
            && address(swolercycles) != address(0)
            && address(smolRacing) != address(0)
            && address(racingTrophies) != address(0);
    }

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __SmolChopShopAdmin_init() internal initializer {
        SmolChopShopView.__SmolChopShopView_init();
    }
}
