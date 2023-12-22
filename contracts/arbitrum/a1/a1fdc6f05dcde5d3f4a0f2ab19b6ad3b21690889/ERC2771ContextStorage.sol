// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

library ERC2771ContextStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.metatx.storage");

    struct Layout {
        address trustedForwarder;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

