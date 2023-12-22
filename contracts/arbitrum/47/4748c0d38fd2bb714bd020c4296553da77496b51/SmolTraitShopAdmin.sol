//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SmolTraitShopView.sol";

/// @title Smol Trait Shop Admin Controls
/// @author Gearhart
/// @notice Admin control functions for SmolTraitShop.

abstract contract SmolTraitShopAdmin is Initializable, SmolTraitShopView {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using StringsUpgradeable for uint256;

// -------------------------------------------------------------
//               External Admin/Owner Functions
// -------------------------------------------------------------

    /// @inheritdoc ISmolTraitShop
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

    /// @inheritdoc ISmolTraitShop
    function changeTraitInfo(
        uint256[] calldata _traitId,
        CreateTraitArgs[] calldata _newTraitInfo
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 amount = _traitId.length;
        _checkLengths(amount, _newTraitInfo.length);
        for (uint256 i = 0; i < amount; i++) {
            uint256 id = _traitId[i];
            _checkTraitId(id);
            CreateTraitArgs calldata _newInfo = _newTraitInfo[i];
            Trait memory trait = traitToInfo[id];
            if (trait.maxSupply != _newInfo.maxSupply) {
                if (_newInfo.maxSupply != 0) {
                    if (_newInfo.maxSupply < trait.amountClaimed) revert InvalidTraitSupply();
                }
                trait.maxSupply = _newInfo.maxSupply;
                trait.uncappedSupply = _newInfo.maxSupply == 0;
            }
            if (trait.forSale != _newInfo.forSale){
                if (trait.forSale && !_newInfo.forSale){
                    _removeTraitFromSale(id);
                }
                else{
                    _addTraitToSale(id);
                }
                trait.forSale = _newInfo.forSale;
            }
            trait.name = _newInfo.name;
            trait.price = _newInfo.price;
            trait.limitedOfferId = _newInfo.limitedOfferId;
            trait.subgroupId = _newInfo.subgroupId;
            trait.tradable = _newInfo.tradable;
            trait.merkleRoot = _newInfo.merkleRoot;
            traitToInfo[id] = trait;
            emit TraitInfoChanged(
                id,
                trait
            );
        }
    }

    /// @inheritdoc ISmolTraitShop
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

    /// @inheritdoc ISmolTraitShop
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

    /// @inheritdoc ISmolTraitShop
    function incrementLimitedOfferId() external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE){
        latestLimitedOffer ++;
    }

    /// @inheritdoc ISmolTraitShop
    function withdrawMagic() external contractsAreSet requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        uint256 contractBalance = magicToken.balanceOf(address(this));
        magicToken.transfer(treasuryAddress, contractBalance);
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

// -------------------------------------------------------------
//                 Essential Setter Functions
// -------------------------------------------------------------

    /// @inheritdoc ISmolTraitShop
    function setContracts(
        address _smolBrains,
        address _smolSchool,
        address _smolsState,
        address _magicToken,
        address _treasuryAddress
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        smolBrains = IERC721(_smolBrains);
        smolSchool = ISchool(_smolSchool);
        smolState = ISmolsState(_smolsState);
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
        && address(smolSchool) != address(0)
        && address(smolState) != address(0)
        && address(magicToken) != address(0)
        && address(treasuryAddress) != address(0);
    }

// -------------------------------------------------------------
//                       Initializer
// -------------------------------------------------------------

    function __SmolTraitShopAdmin_init() internal initializer {
        SmolTraitShopView.__SmolTraitShopView_init();
    }
}
