/**
 * Strategies storage view facet
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./Strategies.sol";
import "./storage_TriggersManager.sol";
import "./Users.sol";
import "./Modifiers.sol";

contract StrategiesViewerFacet is Modifiers {
    // ==================
    //     GETTERS
    // ==================
    function getStrategiesList()
        external
        view
        returns (Vault[] memory strategies)
    {
        strategies = StrategiesStorageLib.retreive().strategies;
    }

    function getStrategyState(
        Vault strategy
    ) external view returns (StrategyState memory strategyState) {
        strategyState = StrategiesStorageLib.retreive().strategiesState[
            strategy
        ];
    }

    function getStrategyGasBalance(
        Vault strategy
    ) external view returns (uint256 vaultGasBalance) {
        vaultGasBalance = StrategiesStorageLib
            .retreive()
            .strategiesState[strategy]
            .gasBalanceWei;
    }

    function getStrategyTriggers(
        Vault strategy
    ) external view returns (RegisteredTrigger[] memory triggers) {
        return
            TriggersManagerStorageLib.retreive().registeredTriggers[strategy];
    }

    function purgeStrategies() external onlyExecutors {
        StrategiesStorageLib.retreive().strategies = new Vault[](0);
    }
}

