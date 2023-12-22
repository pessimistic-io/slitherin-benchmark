/**
 * Storage for the UniV2 LP Adapter
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Struct representing the storage of the UniV2 LP adapter
struct UniV2LpStorage {
    // Mapping client IDs (protocol IDs from the DB) => their addresses
    mapping(bytes32 => address) clientsAddresses;
}

library UniV2LpStorageLib {
    // Storage slot hash
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.adapters.lp.univ2");

    // Retreive the storage struct
    function getUniv2LpStorage()
        internal
        pure
        returns (UniV2LpStorage storage s)
    {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

