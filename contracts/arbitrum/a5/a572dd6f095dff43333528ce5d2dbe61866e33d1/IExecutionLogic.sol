// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IExecutionLogic - ExecutionLogic interface
/// @notice This interface defines the structure for an ExecutionLogic contract.
interface IExecutionLogic {
    // =========================
    // Events
    // =========================

    /// @notice Emits when an execute action is performed.
    /// @param target The address of the contract where the call was made.
    /// @param data The calldata that was executed to `target`.
    event DittoExecute(address indexed target, bytes data);

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when target address for `execute` function is equal vault's address.
    error ExecutionLogic_ExecuteTargetCannotBeAddressThis();

    /// @notice Thrown when the `execute` call has reverted.
    /// @param target The address of the contract where the call was made.
    /// @param data The calldata that caused the revert.
    error ExecutionLogic_ExecuteCallReverted(address target, bytes data);

    // =========================
    // Main functions
    // =========================

    /// @notice Executes a transaction on a `target` contract.
    /// @dev The `target` cannot be the address of this contract.
    /// @param target The address of the contract on which the transaction will be executed.
    /// @param value The amount of Ether to send along with the transaction.
    /// @param data The call data for the transaction.
    /// @return returnData The raw return data from the function call.
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory);

    /// @notice Executes multiple transactions in a single batch.
    /// @dev All transactions are executed on this contract's address.
    /// @dev If a transaction within the batch fails, it will revert.
    /// @param data An array of transaction data.
    function multicall(bytes[] calldata data) external payable;

    /// @notice Executes multiple transactions in a single batch with transfer of Ditto fee.
    /// @dev All transactions are executed on this contract's address.
    /// @dev If a transaction within the batch fails, it will revert.
    /// @param data An array of transaction data.
    function taxedMulticall(bytes[] calldata data) external payable;
}

