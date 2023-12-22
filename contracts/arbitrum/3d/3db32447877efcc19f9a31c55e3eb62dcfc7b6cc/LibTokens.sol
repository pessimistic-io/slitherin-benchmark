// SPDX-License-Identifier: NONE
pragma solidity 0.8.10;
import "./console.sol";
import {LibStorage} from "./LibStorage.sol";

library LibTokens {
    /* Token IDs structure is as follows:
     * - SEED_PETS
     * - RESOURCES
     * - FUNGIBLES/SEMI-FUNGIBLES
     * - NFTs
     */
    /// @notice Reserved IDs for seed pets
    uint64 public constant SEED_PETS_BASE_ID = 1;
    /// @notice Any form of "currency" or important fungible resource we might add
    uint64 public constant RESOURCES_BASE_ID = 5_000; // 5k slots
    uint64 public constant EGGS_BASE_ID = 100_001; // 4096 slots
    uint64 public constant NFTS_BASE_ID = 104_097; // "infinite" slots

    /// @notice Semi-fungibles & fungibles we know beforehand
    uint64 public constant FUNGIBLES_BASE_ID = 10_000; // 90k slots
    // == Resources == //
    uint64 public constant LUX = RESOURCES_BASE_ID + 1;
    uint64 public constant UMBRA = RESOURCES_BASE_ID + 2;
    // == Fungibles == //
    // uint64 public constant HEAD_COSMETIC_PACKAGE_ID = FUNGIBLES_BASE_ID + 1;
    // uint64 public constant EYES_COSMETIC_PACKAGE_ID = FUNGIBLES_BASE_ID + 2;
    // uint64 public constant MOUTH_COSMETIC_PACKAGE_ID = FUNGIBLES_BASE_ID + 3;
    // uint64 public constant TORSO_COSMETIC_PACKAGE_ID = FUNGIBLES_BASE_ID + 4;
    // uint64 public constant LEGS_COSMETIC_PACKAGE_ID = FUNGIBLES_BASE_ID + 5;
    // uint64 public constant HOUSE_ITEM_COSMETIC_PACKAGE_ID =
    //     FUNGIBLES_BASE_ID + 6;
}

