/**
 * A base contract to inherit from which provides some modifiers,
 * using storage from the storage libs.
 *
 * Since libs are not capable of defining modiifers.
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./storage_AccessControl.sol";
import "./Strategies.sol";
import {LibDiamond} from "./LibDiamond.sol";

contract Modifiers {
    /**
     * Only allow owner of the diamond to access
     */
    modifier onlyOwner() {
        require(msg.sender == LibDiamond.contractOwner(), "ERR: Only Owner");
        _;
    }

    /**
     * Only allow a whitelisted executor
     */
    modifier onlyExecutors() {
        require(
            AccessControlStorageLib.getAccessControlStorage().isWhitelisted[
                msg.sender
            ],
            "ERR: Not Whitelisted Executor"
        );
        _;
    }

    /**
     * Only allow vaults to call some function
     */
    modifier onlyVaults() {
        require(
            StrategiesStorageLib
                .getStrategiesStorage()
                .strategiesState[Vault(msg.sender)]
                .registered,
            "Not A Registered Vault"
        );
        _;
    }

    /**
     * Only allow self to call
     */
    modifier onlySelf() {
        require(msg.sender == address(this), "Only Self");
        _;
    }
}

