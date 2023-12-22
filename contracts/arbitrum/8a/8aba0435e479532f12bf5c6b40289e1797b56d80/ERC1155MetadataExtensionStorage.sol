// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

/// @title ERC1155MetadataExtensionStorage
library ERC1155MetadataExtensionStorage {
    struct Layout {
        string name;
        string symbol;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("insrt.contracts.storage.ERC1155MetadataExtensionStorage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;

        assembly {
            l.slot := slot
        }
    }
}

