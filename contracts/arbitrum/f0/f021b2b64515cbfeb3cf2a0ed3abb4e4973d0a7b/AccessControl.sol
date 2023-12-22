/**
 * Access control, managing execution permissions to whitelisted executors
 * @notice Uses the Ownership facet to enforce ownership
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./Strategies.sol";
import "./storage_AccessControl.sol";
import "./Modifiers.sol";
import {LibDiamond} from "./LibDiamond.sol";

contract AccessControlFacet is Modifiers {
    // ======================
    //       GETTERS
    // ======================

    /**
     * Get all executors
     * @return executors - list of all executors
     */
    function getExecutors() external view returns (address[] memory executors) {
        executors = AccessControlStorageLib.getAccessControlStorage().executors;
    }

    /**
     * Whether or not a certain executor is whitelisted
     * @param suspect - The address of the executor to check
     * @return isExecutor - Boolean
     */
    function isAnExecutor(
        address suspect
    ) external view returns (bool isExecutor) {
        isExecutor = AccessControlStorageLib
            .getAccessControlStorage()
            .isWhitelisted[suspect];
    }

    /**
     * Owner/manager
     * @return ownerAddress - The owner of this Diamond
     */
    function getOwner() external view returns (address ownerAddress) {
        ownerAddress = LibDiamond.contractOwner();
    }

    // ======================
    //       FUNCTIONS
    // ======================
    /**
     * @notice
     * Whitelist an executor
     * @param executor - Address of the executor to whitelist
     */
    function whitelistExecutor(address executor) public onlyOwner {
        // Storage ref
        AccessControlStorage
            storage accessControlStorage = AccessControlStorageLib
                .getAccessControlStorage();

        // Avoid dupes
        require(
            !accessControlStorage.isWhitelisted[executor],
            "Executor Already Whitelisted"
        );
        accessControlStorage.executors.push(executor);
        accessControlStorage.isWhitelisted[executor] = true;
    }

    /**
     * @notice
     * Blacklist an executor
     * @param executor - Address of the executor to blacklist
     *
     */
    function blacklistExecutor(address executor) public onlyOwner {
        // Storage ref
        AccessControlStorage
            storage accessControlStorage = AccessControlStorageLib
                .getAccessControlStorage();

        // Avoid dupes
        require(
            accessControlStorage.isWhitelisted[executor],
            "Executor Not Whitelisted"
        );

        // Create a new array of executors
        address[] memory newArr = new address[](
            accessControlStorage.executors.length - 1
        );
        // Push all exsiting executors to it, other than the one to blacklist
        for (uint256 i; i < accessControlStorage.executors.length; i++) {
            if (accessControlStorage.executors[i] == executor) continue;
            newArr[i] = accessControlStorage.executors[i];
        }

        // Set the storage
        accessControlStorage.executors = newArr;
        accessControlStorage.isWhitelisted[executor] = false;
    }
}

