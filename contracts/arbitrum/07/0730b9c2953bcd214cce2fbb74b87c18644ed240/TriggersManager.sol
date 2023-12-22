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

    error TriggerNotReady();

    // =================
    //     MODIFIERS
    // =================

    /**
     * Sponsors a call's gas from a vault's gas balance - When received encoded vault
     * @param encodedVaultRunParams - The vault to take gas from - Encoded
     */
    modifier gasless(bytes calldata encodedVaultRunParams) {
        uint256 startingGas = gasleft();
        // We assume msg.data contains all non-empty bytes, (evm costs 16 gas for non-empty & 4 for empty byte),
        // This is because iterating over all of the bytes and incrementing a cost basis would make the actual calculation
        // cost exponential and thus be not worth it.
        uint256 intrinsicGasCost = 21000 + (msg.data.length * 16);
        (Vault vault, ) = abi.decode(encodedVaultRunParams, (Vault, uint256));
        _; // Marks body of the entire function we are applied to
        uint256 leftGas = gasleft();
        // 2300 for ETH .trasnfer()
        uint256 weiSpent = ((startingGas - leftGas + intrinsicGasCost + 2300) *
            tx.gasprice) + GasManagerStorageLib.getAdditionalGasCost();

        StrategyState storage state = StrategiesStorageLib.getStrategyState(
            vault
        );

        if (weiSpent > state.gasBalanceWei) revert InsufficientGasBalance();

        state.gasBalanceWei -= weiSpent;

        payable(msg.sender).transfer(weiSpent);
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
            storage triggersStorage = TriggersManagerStorageLib.retreive();

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
            storage triggersStorage = TriggersManagerStorageLib.retreive();

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

        if (vault.totalShares() == 0) return false;

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
     * Execute a strategy's trigger with CCIP data
     * @param strategyResponse - Response from CCIP endpoint if request by strategy (otherwise use empty bytes)
     * @param encodedContext - CCIP Extra data (Context of execution - Strategy Index + Trigger Index)
     * ** GasLess - Pays back the gas used **
     */
    function executeStrategyTriggerWithData(
        bytes calldata strategyResponse,
        bytes calldata encodedContext
    ) external gasless(encodedContext) {
        (Vault vault, uint256 strategyTriggerIdx) = abi.decode(
            encodedContext,
            (Vault, uint256)
        );

        _executeTrigger(vault, strategyTriggerIdx, strategyResponse);
    }

    /**
     * Internal function to execute a strategy's trigger
     * @param vault - THe vault to execute a trigger on
     * @param strategyTriggerIdx - Index of the trigger of the strategy mapped to it in storage
     * Note it's external because we want to be able to catch errors here
     */

    function _executeTrigger(
        Vault vault,
        uint256 strategyTriggerIdx,
        bytes memory strategyData
    ) internal {
        try
            TriggersManagerFacet(address(this)).tryExecuteTrigger(
                vault,
                strategyTriggerIdx,
                strategyData
            )
        {} catch (bytes memory revertData) {
            // Only interested in modifying CCIP
            if (bytes4(revertData) != 0x556f1830)
                assembly {
                    revert(revertData, mload(revertData))
                }

            (, string[] memory urls, bytes memory callData, , ) = abi.decode(
                BytesLib.slice(revertData, 4, revertData.length - 4),
                (address, string[], bytes, bytes4, bytes)
            );

            revert OffchainLookup(
                address(this),
                urls,
                callData,
                TriggersManagerFacet.executeStrategyTriggerWithData.selector,
                abi.encode(vault, strategyTriggerIdx)
            );
        }

        TriggersManagerStorageLib
        .retreive()
        .registeredTriggers[vault][strategyTriggerIdx].lastStrategyRun = block
            .timestamp;
    }

    /**
     * Internal function to execute a strategy's trigger
     * @param vault - THe vault to execute a trigger on
     * @param strategyTriggerIdx - Index of the trigger of the strategy mapped to it in storage
     * Note it's external because we want to be able to catch errors here, but shouldnt be called directly
     */
    function tryExecuteTrigger(
        Vault vault,
        uint256 strategyTriggerIdx,
        bytes calldata strategyData
    ) external onlySelf {
        TriggersManagerStorage
            storage triggersStorage = TriggersManagerStorageLib.retreive();

        RegisteredTrigger[] memory registeredTriggers = triggersStorage
            .registeredTriggers[vault];

        RegisteredTrigger memory trigger = registeredTriggers[
            strategyTriggerIdx
        ];

        if (!_checkTrigger(vault, strategyTriggerIdx, trigger))
            revert TriggerNotReady();

        // Switch case
        if (trigger.triggerType == TriggerTypes.AUTOMATION)
            AutomationFacet(address(this)).executeAutomationTrigger(
                vault,
                strategyTriggerIdx,
                strategyData
            );
    }

    // =================
    //     GETTERS
    // =================
    function getVaultTriggers(
        Vault vault
    ) external view returns (RegisteredTrigger[] memory triggers) {
        return TriggersManagerStorageLib.retreive().registeredTriggers[vault];
    }
}

