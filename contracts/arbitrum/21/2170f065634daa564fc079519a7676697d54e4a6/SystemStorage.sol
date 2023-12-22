// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

library SystemStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.system.storage");

    struct Layout {
        bool paused;
        uint128 pausedAt;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

