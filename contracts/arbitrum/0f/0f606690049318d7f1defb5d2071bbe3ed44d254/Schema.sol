/**
 * Contains all different events, structs, enums, etc of the vault
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./automation_Types.sol";

abstract contract VaultTypes {
    // =====================
    //        EVENTS
    // =====================
    /**
     * @notice
     * HydrateRun event
     * Emitted when a new operation request is received (e.g deposit, withdraw, or strategy run), as a request
     * to hydrate it's command calldatas in place.
     * those calldatas are used in steps which are classified as "offchain" steps, whom require some computation
     * to run offchain.
     * @param operationKey - The key of the operation within the operation requests array in storage
     */
    event HydrateRun(uint256 indexed operationKey);

    /**
     * @notice
     * RequestFullfill event,
     * emitted in order to request an offchain fullfill of computations/actions, when simulating them in an hydration run request offchain.
     * @param stepIndex - the index of the step within the run requesting the offchain computation
     * @param ycCommand - The yc command to execute offchain
     */
    event RequestFullfill(uint256 indexed stepIndex, bytes ycCommand);

    /**
     * Deposit
     * Emitted when a deposit happens into the vault
     * @param sender - The user that deposited
     * @param amount - The amount that was deposited
     */
    event Deposit(address indexed sender, uint256 indexed amount);

    /**
     * Withdraw
     * Emitted when a withdrawal finallizes from the vault
     * @param receiver - The user who made the withdraw
     * @param amount - The amount that was withdrawn
     */
    event Withdraw(address indexed receiver, uint256 indexed amount);

    // =====================
    //        ERRORS
    // =====================
    /**
     * Insufficient allownace is thrown when a user attempts to complete an operation (deposit),
     * but has not approved this vault contract for enough tokens
     */
    error InsufficientAllowance();

    /**
     * Insufficient shares is thrown when a user attempts to withdraw an amount of tokens that they do not own.
     */
    error InsufficientShares();

    /**
     * When there is insufficient gas prepayance (msg.value)
     */
    error InsufficientGasPrepay();

    /**
     * When we execute a callback step, there's no calldata hydrated for it and we are on mainnet
     */
    error NoOffchainComputedCommand(uint256 stepIndex);
}

