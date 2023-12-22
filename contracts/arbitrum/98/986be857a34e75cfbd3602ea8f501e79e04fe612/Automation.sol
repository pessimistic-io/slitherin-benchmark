/**
 * Automation Trigger Facet
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./automation_Types.sol";
import "./automation_Types.sol";
import "./triggers_Automation.sol";

contract AutomationFacet {
    /**
     * Register an automation trigger
     * @param automationTrigger - Trigger struct, type must be AUTOMATION
     * @param vault - Vault address to register on
     * @param triggerIdx - Index of the requested trigger
     */
    function registerAutomationTrigger(
        Trigger calldata automationTrigger,
        Vault vault,
        uint256 triggerIdx
    ) public {
        require(
            automationTrigger.triggerType == TriggerTypes.AUTOMATION,
            "Trigger Type Is Not Automation"
        );

        AutomationStorage storage automationStorage = AutomationStorageLib
            .getAutomationStorage();

        uint256 automationInterval = abi.decode(
            automationTrigger.extraData,
            (uint256)
        );

        automationStorage.scheduledAutomations[vault][
            triggerIdx
        ] = ScheduledAutomation(automationInterval, block.timestamp);
    }

    /**
     * Check if an automation trigger should be executed
     * @param vault - The vault to check on
     * @param triggerIdx - The idx of the trigger
     * @return shouldExecute - Whether you should execute this trigger already
     */
    function shouldExecuteAutomationTrigger(
        Vault vault,
        uint256 triggerIdx
    ) public view returns (bool shouldExecute) {
        shouldExecute = _shouldExecuteAutomationTrigger(vault, triggerIdx);
    }

    /**
     * Execute an automation trigger
     * @param vault - The vault to execute an automation trigger on
     * @param triggerIdx - The index of the trigger
     */
    function executeAutomationTrigger(Vault vault, uint256 triggerIdx) public {
        // Re-confirm it should be executed
        if (!_shouldExecuteAutomationTrigger(vault, triggerIdx)) return;

        vault.runStrategy();

        AutomationStorageLib
        .getAutomationStorage()
        .scheduledAutomations[vault][triggerIdx].lastExecutedTimestamp = block
            .timestamp;
    }

    /**
     * Internal function to check the execution condition of the automation
     * @param vault - The vault to check on
     * @param triggerIdx - The idx of the trigger
     * @return shouldExecute - Whether you should execute this trigger already
     */
    function _shouldExecuteAutomationTrigger(
        Vault vault,
        uint256 triggerIdx
    ) internal view returns (bool shouldExecute) {
        AutomationStorage storage automationStorage = AutomationStorageLib
            .getAutomationStorage();

        ScheduledAutomation memory scheduledAutomation = automationStorage
            .scheduledAutomations[vault][triggerIdx];

        shouldExecute =
            block.timestamp - scheduledAutomation.lastExecutedTimestamp >
            scheduledAutomation.interval;
    }
}

