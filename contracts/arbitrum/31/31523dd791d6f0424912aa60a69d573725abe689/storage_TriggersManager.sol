/**
 * Storage for the triggers manager
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";

struct RegisteredTrigger {
    TriggerTypes triggerType;
    uint256 lastStrategyRun;
    uint256 requiredDelay;
}

struct TriggersManagerStorage {
    /**
     * Mapping each vault, to registerd triggers
     */
    mapping(Vault => RegisteredTrigger[]) registeredTriggers;
}

/**
 * The lib to use to retreive the storage
 */
library TriggersManagerStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.triggers_manager");

    // Function to retreive our storage
    function getTriggersStorage()
        internal
        pure
        returns (TriggersManagerStorage storage s)
    {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

