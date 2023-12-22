// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

library SecurityStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.security.storage");

    struct Layout {
        uint256 reentrantStatus;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

