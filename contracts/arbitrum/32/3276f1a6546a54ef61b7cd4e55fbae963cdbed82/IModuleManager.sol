// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Enum} from "./Enum.sol";

/**
 *   @title Fallback Manager - A contract that manages fallback calls made to the Smart Account
 *   @dev Fallback calls are handled by a `handler` contract that is stored at FALLBACK_HANDLER_STORAGE_SLOT
 *        fallback calls are not delegated to the `handler` so they can not directly change Smart Account storage
 */
interface IModuleManager {
    /**
     * @dev Setups module for this Smart Account and enables it.
     * @notice This SHOULD only be done via userOp or a selfcall.
     * @notice Enables the module `module` for the wallet.
     */
    function setupAndEnableModule(address setupContract, bytes memory setupData) external returns (address);

    /**
     * @dev Allows a Module to execute a Smart Account transaction without any further confirmations.
     * @param to Destination address of module transaction.
     * @param value Ether value of module transaction.
     * @param data Data payload of module transaction.
     * @param operation Operation type of module transaction.
     */
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 txGas
    ) external returns (bool success);

    function execTransactionFromModule(address to, uint256 value, bytes memory data, Enum.Operation operation)
        external
        returns (bool);

    /**
     * @dev Allows a Module to execute a wallet transaction without any further confirmations and returns data
     * @param to Destination address of module transaction.
     * @param value Ether value of module transaction.
     * @param data Data payload of module transaction.
     * @param operation Operation type of module transaction.
     * @param txGas Gas limit for module transaction execution.
     */
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 txGas
    ) external returns (bool success, bytes memory returnData);

    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, Enum.Operation operation)
        external
        returns (bool success, bytes memory returnData);

    /**
     * @dev Allows a Module to execute a batch of Smart Account transactions without any further confirmations.
     * @param to Destination address of module transaction.
     * @param value Ether value of module transaction.
     * @param data Data payload of module transaction.
     * @param operations Operation type of module transaction.
     */
    function execBatchTransactionFromModule(
        address[] calldata to,
        uint256[] calldata value,
        bytes[] calldata data,
        Enum.Operation[] calldata operations
    ) external returns (bool success);

    /**
     * @dev Returns if a module is enabled
     * @return True if the module is enabled
     */
    function isModuleEnabled(address module) external view returns (bool);
}

