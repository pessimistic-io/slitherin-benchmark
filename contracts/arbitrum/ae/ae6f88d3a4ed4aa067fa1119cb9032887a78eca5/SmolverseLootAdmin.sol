//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Initializable} from "./Initializable.sol";
import {SmolverseLootContracts} from "./SmolverseLootContracts.sol";

abstract contract SmolverseLootAdmin is Initializable, SmolverseLootContracts {
    function __SmolverseLootAdmin_init() internal initializer {
        SmolverseLootContracts.__SmolverseLootContracts_init();
    }

    function addLoots(uint256[] calldata _lootIds, Loot[] calldata _loots) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        for (uint256 i = 0; i < _lootIds.length; i++) {
            Loot memory loot = _loots[i];

            if (loot.shape == 0 || loot.color == 0) revert InvalidLoot(_lootIds[i], loot);
            if (loots[_lootIds[i]].shape > 0) revert ExistingLoot(_lootIds[i], loot);


            lootIds++;
            loots[_lootIds[i]] = loot;
            emit LootAdded(_lootIds[i], loot);
        }
    }

    function overrideLoots(
        uint256[] calldata _lootIds,
        Loot[] calldata _loots
    ) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        for (uint256 index = 0; index < _lootIds.length; index++) {
            uint256 lootId = _lootIds[index];
            Loot memory loot = _loots[index];

            if (loot.shape == 0 || loot.color == 0) revert InvalidLoot(lootId, loot);
            if (lootId > lootIds) revert InvalidLootId(lootId);

            loots[lootId] = loot;
            emit LootUpdated(lootId, loot);
        }
    }

    function setTraitShopSkinsMerkleRoot(bytes32 _traitShopSkinsMerkleRoot) external requiresEitherRole(ADMIN_ROLE, OWNER_ROLE) {
        traitShopSkinsMerkleRoot = _traitShopSkinsMerkleRoot;
    }

    function setBaseURI(string calldata _newBaseURI) external requiresEitherRole(OWNER_ROLE, ADMIN_ROLE){
        baseURI = _newBaseURI;
    }
    function setCollectionDescription(string calldata _newCollectionDescription) external requiresEitherRole(OWNER_ROLE, ADMIN_ROLE){
        collectionDescription = _newCollectionDescription;
    }

}

