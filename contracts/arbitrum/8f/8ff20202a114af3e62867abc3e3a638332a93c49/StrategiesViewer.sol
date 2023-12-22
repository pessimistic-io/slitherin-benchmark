/**
 * Strategies storage view facet
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./Strategies.sol";
import "./Users.sol";
import "./ERC20.sol";
// import "../triggers/Registry.sol";
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
        strategies = StrategiesStorageLib.getStrategiesStorage().strategies;
    }

    function getStrategyState(
        Vault strategy
    ) external view returns (StrategyState memory strategyState) {
        strategyState = StrategiesStorageLib
            .getStrategiesStorage()
            .strategiesState[strategy];
    }

    function getStrategyGasBalance(
        Vault strategy
    ) external view returns (uint256 vaultGasBalance) {
        vaultGasBalance = StrategiesStorageLib
            .getStrategiesStorage()
            .strategiesState[strategy]
            .gasBalanceWei;
    }

    function getStrategyOperationGas(
        Vault strategy,
        uint256 opIndex
    ) external view returns (uint256 strategyOperationGas) {
        strategyOperationGas = StrategiesStorageLib
            .getStrategiesStorage()
            .strategyOperationsGas[strategy][opIndex];
    }
}

