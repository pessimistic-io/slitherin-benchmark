// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

library OwnableStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.access.ownable");

    struct Layout {
        address owner;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function setOwner(Layout storage l, address owner) internal {
        l.owner = owner;
    }
}

