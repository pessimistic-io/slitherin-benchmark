// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

string constant ITEM_COLLECTION_NAME = "Realm Rarity items";
string constant ITEM_COLLECTION_DESCRIPTION = "Rarity items description";

//================================================
// Item-related constants, characteristics
//================================================

uint16 constant ITEM_CHARACTERISTIC_RARITY = 0;
uint16 constant ITEM_CHARACTERISTIC_SLOT = 1;
// "Weapon" slot could have "Heavy Weapon", "Magic Weapon", "Ranged Weapon"
uint16 constant ITEM_CHARACTERISTIC_CATEGORY = 2;
// Specific items in a given slot+category
// Heavy Weapon would be "Mallet" or "Great Axe", ranged weapon would be "Bow", "Crossbow", "Rifle"
uint16 constant ITEM_CHARACTERISTIC_TYPE = 3;
uint16 constant ITEM_CHARACTERISTIC_PREFIX = 4;
uint16 constant ITEM_CHARACTERISTIC_SUFFIX = 5;

uint16 constant ITEM_SLOT_HEAD = 1;
uint16 constant ITEM_SLOT_CHEST = 2;
uint16 constant ITEM_SLOT_HAND = 3;
uint16 constant ITEM_SLOT_JEWELRY = 4;

uint16 constant ITEM_TYPE_HEADGEAR = 1;
uint16 constant ITEM_TYPE_ARMOR = 2;
uint16 constant ITEM_TYPE_APPAREL = 3;
uint16 constant ITEM_TYPE_JEWELRY = 4;
uint16 constant ITEM_TYPE_WEAPON = 5;

uint16 constant ITEM_RARITY_COMMON = 1;
uint16 constant ITEM_RARITY_RARE = 2;
uint16 constant ITEM_RARITY_EPIC = 3;
uint16 constant ITEM_RARITY_LEGENDARY = 4;
uint16 constant ITEM_RARITY_MYTHIC = 5;
uint16 constant ITEM_RARITY_EXOTIC = 6;

