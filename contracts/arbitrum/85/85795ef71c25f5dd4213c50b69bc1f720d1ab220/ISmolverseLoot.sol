// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ISmolverseLoot {
    error InvalidLoot(uint256 lootId, Loot loot);
    error InvalidLootId(uint256 lootId);
    error ExistingLoot(uint256 lootId, Loot loot);
    error NotOwner(uint256 tokenId, address operator);
    error InvalidTreasure(uint256 treasureId);
    error InvalidCraft(RainbowTreasureCraftInput rainbowTreasureCraftInput);
    error UserHasAlreadyClaimedSkinLoot(address _user);
    error UserIsNotInMerkleTree(address _user);
    error SmolIsNotFemale(uint256 _tokenId);

    event LootAdded(uint256 lootId, Loot loot);
    event LootUpdated(uint256 lootId, Loot loot);
    event LootTokenMinted(uint256 tokenId, LootToken lootToken);
    event LootTokenRerolled(uint256 tokenId, LootToken lootToken);

    enum CraftType {
        BY_SHAPE,
        BY_COLOR
    }

    struct LootConversionInput {
        uint256[] smolCarIds;
        uint256[] swolercycleIds;
        uint256[] treasureIds;
        uint256[] smolPetIds;
        uint256[] swolPetIds;
        uint256[] treasureAmounts;
        uint256[] vehicleSkinIds;
        bytes32[] merkleProofsForSmolTraitShop;
        uint256 smolTraitShopSkinCount;
        uint256[] smolFemaleIds;
    }

    struct RainbowTreasureCraftInput {
        uint256[] tokenIds;
        CraftType craftType;
    }

    struct Loot {
        uint8 color;
        uint8 shape;
        string colorName;
        string shapeName;
    }

    struct LootToken {
        uint16 lootId;
        uint40 expireAt;
    }

    function mintLootsAsAdmin(address, uint256) external;
}
