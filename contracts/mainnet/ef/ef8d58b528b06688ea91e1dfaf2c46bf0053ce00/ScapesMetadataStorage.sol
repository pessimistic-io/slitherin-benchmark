// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {strings} from "./strings.sol";

library ScapesMetadataStorage {
    using strings for *;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("scapes.storage.Metadata");

    struct Trait {
        uint128 filter;
        uint8 shift;
        uint8 startIdx;
        bool isLandmark;
        string[] names;
    }

    struct Layout {
        uint256[3334] scapeData;
        mapping(string => mapping(uint256 => int256[])) landmarkOffsets;
        mapping(string => string) variationNames;
        string[16] traitNames;
        mapping(string => Trait) traits;
    }

    function layout() internal pure returns (Layout storage d) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            d.slot := slot
        }
    }
}

