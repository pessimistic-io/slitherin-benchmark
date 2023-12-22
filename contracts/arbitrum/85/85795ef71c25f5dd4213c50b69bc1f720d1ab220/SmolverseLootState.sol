//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";

import {ISmolverseLoot} from "./ISmolverseLoot.sol";
import {UtilitiesV3Upgradeable} from "./UtilitiesV3Upgradeable.sol";

abstract contract SmolverseLootState is Initializable, ISmolverseLoot, UtilitiesV3Upgradeable {
    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant RAINBOW_TREASURE_ID = 10;
    address internal smolCarsAddress;
    address internal swolercyclesAddress;
    address internal treasuresAddress;
    address internal magicAddress;
    address internal smolChopShopAddress;
    address internal smolPetsAddress;
    address internal swolPetsAddress;
    address internal smolBrainsAddress;
    address internal smolsStateAddress;

    address public troveAddress;

    uint256 internal tokenIds;
    uint256 internal lootIds;

    bytes32 public traitShopSkinsMerkleRoot;

    bytes32 internal constant SMOL_LOOT_MINTER_ROLE = keccak256("SMOL_LOOT_MINTER");

    string public baseURI;
    string public collectionDescription;


    mapping(uint256 => LootToken) public lootTokens;
    mapping(uint256 => Loot) public loots;

    mapping(address => bool) public hasClaimedSkinLoot;

    function __SmolverseLootState_init() internal initializer {
        UtilitiesV3Upgradeable.__Utilities_init();
    }
}

