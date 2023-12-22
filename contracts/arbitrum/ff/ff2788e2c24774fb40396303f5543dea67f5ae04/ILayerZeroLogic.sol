// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ILayerZeroLogic - LayerZeroLogic interface.
interface ILayerZeroLogic {
    // =========================
    // Errors
    // =========================

    /// @dev Error indicating that the vault is not permitted to use cross-chain logic.
    error LayerZeroLogic_VaultCannotUseCrossChainLogic();

    /// @dev Error indicating that only the Ditto Bridge Receiver is authorized to call the method.
    error LayerZeroLogic_OnlyDittoBridgeReceiverCanCallThisMethod();

    // =========================
    // Main functions
    // =========================

    struct LayerZeroTxParams {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        address dstNativeAddr;
        // currently address(0)
        address zroPaymentAddress;
        // currently false
        bool payInZRO;
    }

    /// @notice Sends a LayerZero cross-chain message to a specified destination chain.
    /// @dev This function prepares and sends a cross-chain message via the LayerZero infrastructure.
    /// @param dstChainId The ID of the destination chain to which the message should be sent.
    /// @param lzTxParams The transaction parameters required for the cross-chain message.
    /// @param payload The payload data of the message.
    function sendLayerZeroMessage(
        uint256 vaultVersion,
        uint16 dstChainId,
        LayerZeroTxParams calldata lzTxParams,
        bytes calldata payload
    ) external payable;

    /// @notice Executes multiple calls in a single transaction on LayerZero.
    /// @dev This function uses the Multicall pattern to aggregate multiple function calls into a single transaction.
    /// @param data An array of encoded function call data.
    function layerZeroMulticall(bytes[] calldata data) external;
}

