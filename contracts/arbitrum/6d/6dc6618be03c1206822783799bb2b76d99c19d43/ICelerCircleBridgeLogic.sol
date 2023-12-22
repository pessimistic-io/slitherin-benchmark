/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICelerCircleBridgeLogic - CelerCircleBridgeLogic interface.
/// @dev Provides the main functionality for the CelerCircleBridgeLogic.
interface ICelerCircleBridgeLogic {
    // =========================
    // Errors
    // =========================

    /// @notice Indicates that the vault cannot use cross chain logic.
    error CelerCircleBridgeLogic_VaultCannotUseCrossChainLogic();

    /// @notice Indicates that the arguments provided to the multisender are not valid.
    error CelerCircleBridgeLogic_MultisenderArgsNotValid();

    // =========================
    // Main functions
    // =========================

    /// @notice Sends a CelerCircle USDC transfer to a specified chain.
    /// @dev Allows for cross-chain communication with the specified chain.
    /// @param dstChainId The destination chain ID where the USDC transfer will be sent.
    /// @param exactAmount The exact amount to be sent.
    /// @param recipient The address of the recipient on the destination chain.
    function sendCelerCircleMessage(
        uint64 dstChainId,
        uint256 exactAmount,
        address recipient
    ) external;

    /// @notice Sends a batch of CelerCircle USDC transfers to a specified chain.
    /// @dev Allows for sending multiple USDC transfers in a single transaction.
    /// @param dstChainId The destination chain ID where the USDC transfers will be sent.
    /// @param exactAmount Array of exact amounts to be sent.
    /// @param recipient Array of recipient addresses on the destination chain.
    function sendBatchCelerCircleMessage(
        uint64 dstChainId,
        uint256[] calldata exactAmount,
        address[] calldata recipient
    ) external;
}

