/**
 * Facet to register, check on & execute triggers
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Modifiers.sol";
import "./automation_Types.sol";
import "./storage_TriggersManager.sol";
import "./Strategies.sol";
import "./triggers_Automation.sol";
import "./StrategiesViewer.sol";
import {GasManagerStorageLib} from "./GasManager.sol";
import {BytesLib} from "./BytesLib.sol";

contract TriggersManagerFacet is Modifiers {
    // =================
    //      ERRORS
    // =================
    error InsufficientGasBalance();

    error OffchainLookup(
        address sender,
        string[] urls,
        bytes callData,
        bytes4 callbackFunction,
        bytes extraData
    );

    // =================
    //     MODIFIERS
    // =================
    /**
     * Sponsors a call's gas from a vault's gas balance
     * @param vault - The vault to take gas from
     * @param executor - The executor to send the ETH to
     */
    modifier gasless(Vault vault, address payable executor) {
        uint256 startingGas = gasleft();
        _; // Marks body of the entire function we are applied to
        uint256 leftGas = gasleft();

        uint256 weiSpent = ((startingGas - leftGas) * tx.gasprice) +
            GasManagerStorageLib.getAdditionalGasCost();

        StrategyState storage state = StrategiesStorageLib.getStrategyState(
            vault
        );

        if (weiSpent > state.gasBalanceWei) revert InsufficientGasBalance();

        state.gasBalanceWei -= weiSpent;

        executor.transfer(weiSpent);
    }

    // =================
    //     FUNCTIONS
    // =================

    // ==========
    //  REGISTER
    // ==========
    /**
     * Register multiple triggers
     * @param triggers - Array of the trigger structs to register
     * @param vault - The strategy address to register the triggers on
     */
    function registerTriggers(
        Trigger[] calldata triggers,
        Vault vault
    ) public onlySelf {
        TriggersManagerStorage
            storage triggersStorage = TriggersManagerStorageLib
                .getTriggersStorage();

        for (uint256 i; i < triggers.length; i++) {
            triggersStorage.registeredTriggers[vault].push(
                RegisteredTrigger(
                    triggers[i].triggerType,
                    block.timestamp,
                    60 // TODO: Integrate delays from user end
                )
            );

            if (triggers[i].triggerType == TriggerTypes.AUTOMATION)
                return
                    AutomationFacet(address(this)).registerAutomationTrigger(
                        triggers[i],
                        vault,
                        i
                    );
        }
    }

    // ==========
    //  CHECK
    // ==========
    /**
     * Check all triggers of all strategies
     * @return triggersStatus - 2D Array of booleans, each index is a strategy and has an array of booleans
     * (it's trigger indices, whether it should exec them)
     */
    function checkStrategiesTriggers()
        external
        view
        returns (bool[][] memory triggersStatus)
    {
        Vault[] memory vaults = StrategiesViewerFacet(address(this))
            .getStrategiesList();

        TriggersManagerStorage
            storage triggersStorage = TriggersManagerStorageLib
                .getTriggersStorage();

        triggersStatus = new bool[][](vaults.length);

        for (uint256 i; i < vaults.length; i++) {
            Vault vault = vaults[i];

            RegisteredTrigger[] memory registeredTriggers = triggersStorage
                .registeredTriggers[vault];

            bool[] memory vaultTriggersStatus = new bool[](
                registeredTriggers.length
            );

            for (
                uint256 triggerIdx;
                triggerIdx < registeredTriggers.length;
                triggerIdx++
            ) {
                vaultTriggersStatus[triggerIdx] = _checkTrigger(
                    vault,
                    triggerIdx,
                    registeredTriggers[triggerIdx]
                );
            }

            if (vaultTriggersStatus.length > 0)
                triggersStatus[i] = vaultTriggersStatus;
        }
    }

    /**
     * Check a single trigger condition (internal)
     * @param vault - The vault to check
     * @param triggerIdx - The trigger index to check
     * @param trigger - The actual registered trigger
     * @return shouldTrigger
     */
    function _checkTrigger(
        Vault vault,
        uint256 triggerIdx,
        RegisteredTrigger memory trigger
    ) internal view returns (bool shouldTrigger) {
        // The required delay registered for the trigger to run
        if (block.timestamp - trigger.lastStrategyRun < trigger.requiredDelay)
            return false;

        if (trigger.triggerType == TriggerTypes.AUTOMATION)
            return
                AutomationFacet(address(this)).shouldExecuteAutomationTrigger(
                    vault,
                    triggerIdx
                );

        return false;
    }

    // ==========
    //    EXEC
    // ==========
    /**
     * Execute multiple strategies' checked triggers
     * @param vaultsIndices - Indices of the vaults from storage to execute
     * @param triggersSignals - 2D boolean array, has to be of same length as indices array, indicates for each
     * registered strategy whether it should run
     */
    function executeStrategiesTriggers(
        uint256[] calldata vaultsIndices,
        bool[][] calldata triggersSignals
    ) external {
        require(
            vaultsIndices.length == triggersSignals.length,
            "Vaults Indices & Triggers Signals Mismatch"
        );

        Vault[] memory vaults = StrategiesStorageLib
            .getStrategiesStorage()
            .strategies;

        for (uint256 i; i < vaultsIndices.length; i++)
            _executeStrategyTriggers(
                vaults[vaultsIndices[i]],
                triggersSignals[i]
            );
    }

    /**
     * Execute a strategy's checked triggers (Internal)
     * @param vault - The vault to execute the triggers on
     * @param triggersSignals - Boolean array the length of the registered triggers,
     * indicating whether to execute it or not.
     */
    function _executeStrategyTriggers(
        Vault vault,
        bool[] calldata triggersSignals
    ) internal {
        TriggersManagerStorage
            storage triggersStorage = TriggersManagerStorageLib
                .getTriggersStorage();

        RegisteredTrigger[] memory registeredTriggers = triggersStorage
            .registeredTriggers[vault];

        require(
            triggersSignals.length == registeredTriggers.length,
            "Trigger Signals & Registered Triggers Length Mismatch"
        );

        for (uint256 i; i < registeredTriggers.length; i++) {
            if (!triggersSignals[i]) continue;

            // Additional, trust-minimized sufficient check
            if (!_checkTrigger(vault, i, registeredTriggers[i])) continue;

            // DK how to ignore return value
            try
                TriggersManagerFacet(address(this))._executeTrigger(
                    vault,
                    i,
                    registeredTriggers[i],
                    payable(msg.sender)
                )
            {} catch (bytes memory customRevert) {
                // Bubble revert up if not an offchain lookup
                if (bytes4(customRevert) != 0x556f1830)
                    assembly {
                        revert(customRevert, mload(customRevert))
                    }
            }

            triggersStorage.registeredTriggers[vault][i].lastStrategyRun = block
                .timestamp;
        }
    }

    /**
     * Execute a single trigger condition (internal)
     * @param vault - The vault to execute on
     * @param triggerIdx - The trigger index to execute
     * @param trigger - The actual registered trigger (For types)
     * Note that this is an external function, but only we can call it.
     * The reason it is like that is because it's supposed to be called as apart
     * of a batch execution of multiple strategies, but we do not want to retain the same execution context,
     * to avoid reverting everything, and being able to still protect executor's gas fees
     */
    function _executeTrigger(
        Vault vault,
        uint256 triggerIdx,
        RegisteredTrigger memory trigger,
        address payable executor
    ) external gasless(vault, executor) onlySelf {
        if (trigger.triggerType == TriggerTypes.AUTOMATION)
            AutomationFacet(address(this)).executeAutomationTrigger(
                vault,
                triggerIdx
            );
    }

    // =================
    //     GETTERS
    // =================
    function getVaultTriggers(
        Vault vault
    ) external view returns (RegisteredTrigger[] memory triggers) {
        return
            TriggersManagerStorageLib.getTriggersStorage().registeredTriggers[
                vault
            ];
    }
}

