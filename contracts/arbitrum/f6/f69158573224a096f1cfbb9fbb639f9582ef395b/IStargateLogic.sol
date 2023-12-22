// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStargateComposer} from "./IStargateComposer.sol";

/// @title IStargateLogic - StargateLogic interface
interface IStargateLogic {
    // =========================
    // Storage
    // =========================

    struct StargateLogicStorage {
        /// @notice Temporary value storing the exact number of tokens that were sent through the startgate protocol.
        /// @dev Set at the beginning of the stargateMulticall function and reset at the end.
        uint256 bridgedAmount;
    }

    // =========================
    // Error
    // =========================

    /// @notice Thrown when a vault tries to use cross-chain logic.
    error StargateLogic_VaultCannotUseCrossChainLogic();

    /// @notice Thrown when someone other than the Ditto bridge receiver tries to call a restricted method.
    error StargateLogic_OnlyDittoBridgeReceiverCanCallThisMethod();

    /// @notice Thrown when the multisender parameters do not have matching lengths.
    error StargateLogic_MultisenderParamsDoNotMatchInLength();

    /// @notice Thrown when the contract does not have enough balance to cover the fees.
    error StargateLogic_NotEnoughBalanceForFee();

    // =========================
    // Main functions
    // =========================

    /// @notice Send assets through the stargate to another chain.
    /// @param vaultVersion: Version to which the vault will be deployed on the destination chain.
    /// @param dstChainId: Destination chain Id.
    /// @param srcPoolId: Source pool Id.
    /// @param dstPoolId: Destination pool Id.
    /// @param bridgeAmount: Amount of tokens to send through the bridge.
    /// @param amountOutMinSg: Minimum amount to be received on the other side of the bridge.
    /// @param lzTxParams: Parameters for the layer zero transaction.
    /// @param payload: Data payload.
    function sendStargateMessage(
        uint256 vaultVersion,
        uint16 dstChainId,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 bridgeAmount,
        uint256 amountOutMinSg,
        IStargateComposer.lzTxObj calldata lzTxParams,
        bytes calldata payload
    ) external payable;

    struct MultisenderParams {
        uint16 dstChainId;
        uint256 srcPoolId;
        uint256 dstPoolId;
        uint256 slippageE18;
        address[] recipients;
        uint256[] tokenShares;
    }

    /// @notice Distribute tokens to multiple recipients using Stargate.
    /// @dev This function can only be called by the ditto Stargate receiver.
    /// @param bridgeAmount: Total amount of tokens to distribute.
    /// @param mParams: Parameters for multisender distribution.
    function stargateMultisender(
        uint256 bridgeAmount,
        MultisenderParams calldata mParams
    ) external payable;

    /// @notice Executes multiple transactions in a single batch via Stargate.
    /// @dev All transactions are executed on this contract's address.
    /// @dev If a transaction within the batch fails, it will revert.
    /// @param bridgedAmount: An exact amount of tokens transferred via Stargate.
    /// @param data: An array of transaction data.
    function stargateMulticall(
        uint256 bridgedAmount,
        bytes[] calldata data
    ) external;
}

