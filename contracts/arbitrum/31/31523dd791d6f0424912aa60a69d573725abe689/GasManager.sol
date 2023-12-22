/**
 * Storage for the gas manager
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import {IGasHook} from "./IGasHook.sol";

struct GasManagerStorage {
    /**
     * Current L2 hook, that returns additional gas costs to charge the vault's gas blance,
     * that the usual gasleft() does not include
     */
    IGasHook gasHook;
}

/**
 * The lib to use to retreive the storage
 */
library GasManagerStorageLib {
    // The namespace for the lib (the hash where its stored)
    bytes32 internal constant STORAGE_NAMESPACE =
        keccak256("diamond.yieldchain.storage.strategies");

    // Function to retreive our storage
    function retreive() internal pure returns (GasManagerStorage storage s) {
        bytes32 position = STORAGE_NAMESPACE;
        assembly {
            s.slot := position
        }
    }

    function getAdditionalGasCost()
        internal
        view
        returns (uint256 additionalWeiCost)
    {
        IGasHook hook = retreive().gasHook;
        if (address(hook) == address(0)) return 0;

        additionalWeiCost = hook.getAdditionalGasCost();
    }
}

