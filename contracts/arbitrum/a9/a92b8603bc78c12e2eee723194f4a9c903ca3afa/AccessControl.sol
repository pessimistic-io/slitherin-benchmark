/**
 * Storage for managing executors access control
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";

struct AccessControlStorage {
    /**
     * Owner of the diamond
     */
    address owner;
    /**
     * Iterable mapping for whitelisted executors
     */
    address[] executors;
    mapping(address => bool) isWhitelisted;
    /**
     * The current CCIP gateway URL used for Offchain Actions
     */
    string offchainActionsUrl;
}

/**
 * The lib to use to retreive the storage
 */
library AccessControlStorageLib {
    // ======================
    //       STORAGE
    // ======================
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.access_control");

    // Function to retreive our storage
    function getAccessControlStorage()
        internal
        pure
        returns (AccessControlStorage storage s)
    {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }

    function _setOffchainLookupUrl(string calldata newUrl) internal {
        AccessControlStorage
            storage accessControlStorage = getAccessControlStorage();
        accessControlStorage.offchainActionsUrl = newUrl;
    }

    function _getOffchainLookupUrl()
        internal
        view
        returns (string memory offchainurl)
    {
        offchainurl = getAccessControlStorage().offchainActionsUrl;
    }
}

