/**
 * Facet to register, check on & execute triggers
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Modifiers.sol";
import "./automation_Types.sol";
import "./storage_TriggersManager.sol";
import "./triggers_Automation.sol";
import "./StrategiesViewer.sol";

contract TriggersManagerFacet is Modifiers {
    // =================
    //     FUNCTIONS
    // =================
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
            triggersStorage.registeredTriggers[vault][i] = RegisteredTrigger(
                triggers[i].triggerType,
                block.timestamp,
                60 // TODO: Integrate delays from user end
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
            )
                vaultTriggersStatus[i] = _checkTrigger(
                    vault,
                    triggerIdx,
                    registeredTriggers[triggerIdx]
                );

            triggersStatus[i] = vaultTriggersStatus;
        }
    }

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
            _executeStrategyTriggers(vaults[i], triggersSignals[i]);
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

            _executeTrigger(vault, i, registeredTriggers[i]);

            triggersStorage.registeredTriggers[vault][i].lastStrategyRun = block
                .timestamp;
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

    /**
     * Execute a single trigger condition (internal)
     * @param vault - The vault to execute on
     * @param triggerIdx - The trigger index to execute
     * @param trigger - The actual registered trigger (For types)
     */
    function _executeTrigger(
        Vault vault,
        uint256 triggerIdx,
        RegisteredTrigger memory trigger
    ) internal {
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

