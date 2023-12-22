/**
 * Manages vaults' gas balances, and gas fees stuff
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Vault.sol";
import "./Strategies.sol";
import "./Users.sol";
import "./ERC20.sol";
// import "../triggers/Registry.sol";
import "./Modifiers.sol";

contract GasManagerFacet is Modifiers {
    /**
     * @notice
     * Fund a vault's native gas balance (Used to fund trigger runs)
     * @param strategyAddress - Address of the strategy to fund
     */
    function fundGasBalance(address strategyAddress) public payable {
        /**
         * Shorthand for strategies storage
         */
        StrategiesStorage storage strategiesStorage = StrategiesStorageLib
            .getStrategiesStorage();
        /**
         * Storage ref to our strategy in the mapping
         */
        StrategyState storage strategy = strategiesStorage.strategiesState[
            Vault(strategyAddress)
        ];

        /**
         * Require the strategy to exist
         */
        require(strategy.registered, "Vault Does Not Exist");

        /**
         * Finally, increment the gas balance in the amount provided
         */
        strategy.gasBalanceWei += msg.value;
    }

    /**
     * @notice
     * stashOperationGas()
     * Allows strategies to stash some native gas for an operation
     * @param operationIndex - Index of the operation it's stashing for
     */
    function stashOperationGas(
        uint256 operationIndex
    ) external payable onlyVaults {
        StrategiesStorageLib.getStrategiesStorage().strategyOperationsGas[
            Vault(msg.sender)
        ][operationIndex] += msg.value;
    }

    /**
     * @notice
     * collectVaultGasDebt()
     * Deduct from a vault's gas balance, and transfer it to some address
     * can only be called internally!!
     * @param strategy - Address of the strategy to deduct
     * @param receiver - The address of the Ether receiver
     * @param debtInWei - The debt of the strategy in WEI (not GWEI!!) to deduct
     */
    function collectVaultGasDebt(
        Vault strategy,
        address payable receiver,
        uint256 debtInWei
    ) public onlySelf {
        // Shorthand for strategies storage
        StrategiesStorage storage strategiesStorage = StrategiesStorageLib
            .getStrategiesStorage();

        // Storage ref to our strategy in the mapping
        StrategyState storage strategyState = strategiesStorage.strategiesState[
            strategy
        ];

        // Assert that the balance is sufficient and deduct the debt
        require(
            strategyState.gasBalanceWei >= debtInWei,
            "Insufficient Gas Balance To Deduct."
        );

        // Deduct it
        strategyState.gasBalanceWei -= debtInWei;

        // Transfer to the receiver
        receiver.transfer(debtInWei);
    }
}

