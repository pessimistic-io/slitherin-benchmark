/**
 * User-related storage for the YC Diamond.
 * Mainly used for analytical purposes of users,
 * and managing premium users
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";

struct UsersStorage {
    /**
     * Mapping user addresses => Whether they are premium or not
     */
    mapping(address => bool) isPremium;
    /**
     * Mapping user addresses => Their portfolio vaults.
     * Each time someone deposits/withdraws into a vault, it will call a function on our facet and
     * update the user's portfolio accordingly
     */
    mapping(address => Vault[]) portfolios;
}

/**
 * The lib to use to retreive the storage
 */
library UsersStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.users");

    // Function to retreive our storage
    function retreive() internal pure returns (UsersStorage storage s) {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

