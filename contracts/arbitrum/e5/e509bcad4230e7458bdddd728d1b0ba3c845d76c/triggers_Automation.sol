/**
 * Storage For The Automation Facet
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./automation_Types.sol";

struct AutomationStorage {
    /**
     * Mapping each registered strategy to a trigger idx to an ScheduledAutomation struct
     */
    mapping(Vault => mapping(uint256 => ScheduledAutomation)) scheduledAutomations;
}

/**
 * The lib to use to retreive the storage
 */
library AutomationStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.triggers.automation");

    // Function to retreive our storage
    function getAutomationStorage()
        internal
        pure
        returns (AutomationStorage storage s)
    {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }
}

