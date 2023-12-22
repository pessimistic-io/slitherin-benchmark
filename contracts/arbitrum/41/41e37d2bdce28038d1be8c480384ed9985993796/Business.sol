/**
 * Business related storage
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct BusinessStorage {
    address treasury;
}

/**
 * The lib to use to retreive the storage
 */
library BusinessStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.business");

    // Function to retreive our storage
    function retreive() internal pure returns (BusinessStorage storage s) {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

