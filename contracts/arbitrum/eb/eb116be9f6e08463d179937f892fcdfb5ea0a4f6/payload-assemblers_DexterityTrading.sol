/**
 * Storage specific to the DexterityTrading payload facet
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct DexterityTradingStorage {
    /**
     * Map user address => nonce
     */
    mapping(address => uint64) nonces;
    /**
     * Identifier of the Dexterity Trading processor on Solana
     */
    bytes8 dexterityProcessorSelector;
}

/**
 * The lib to use to retreive the storage
 */
library DexterityTradingStorageLib {
    // ======================
    //       STORAGE
    // ======================
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256(
            "diamond.hxro.storage.facets.payload_assemblers.dexterity_trading"
        );

    // Function to retreive our storage
    function retreive()
        internal
        pure
        returns (DexterityTradingStorage storage s)
    {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }

    function _getAndIncrementNonce(
        address user
    ) internal returns (uint256 oldNonce) {
        DexterityTradingStorage storage dexterityStorage = retreive();
        oldNonce = dexterityStorage.nonces[user];
        dexterityStorage.nonces[user]++;
    }
}

