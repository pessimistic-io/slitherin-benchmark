// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

struct Hedger {
    address addr;
}

library HedgersStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.hedgers.storage");

    struct Layout {
        mapping(address => Hedger) hedgerMap;
        Hedger[] hedgerList;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

