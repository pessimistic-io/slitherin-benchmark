// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ILayerZeroEndpoint} from "./ILayerZeroEndpoint.sol";

import {BridgeLogicBase} from "./BridgeLogicBase.sol";
import {TransferHelper} from "./TransferHelper.sol";

import {ILayerZeroLogic} from "./ILayerZeroLogic.sol";

/// @title LayerZeroLogic
contract LayerZeroLogic is ILayerZeroLogic, BridgeLogicBase {
    // =========================
    // Constructor
    // =========================

    /// @dev Address of the stargate composer for cross-chain messaging
    ILayerZeroEndpoint private immutable layerZeroEndpoint;

    /// @notice Initializes the contract with the layer zero endpoint and ditto layer zero receiver addresses.
    /// @param _layerZeroEndpoint: Address of the layer zero endpoint.
    /// @param _dittoLayerZeroReceiver: Address of the ditto layer zero receiver.
    constructor(
        address _layerZeroEndpoint,
        address _dittoLayerZeroReceiver
    ) BridgeLogicBase(_dittoLayerZeroReceiver) {
        layerZeroEndpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc ILayerZeroLogic
    function sendLayerZeroMessage(
        uint256 vaultVersion,
        uint16 dstChainId,
        LayerZeroTxParams calldata lzTxParams,
        bytes calldata payload
    ) external payable onlyVaultItself {
        (address owner, uint16 vaultId) = _validateBridgeCall(
            LayerZeroLogic_VaultCannotUseCrossChainLogic.selector
        );

        bytes memory newPayload = abi.encode(
            owner,
            vaultVersion,
            vaultId,
            payload
        );

        bytes memory adapterParam = _txParamBuilder(
            lzTxParams.dstGasForCall,
            lzTxParams.dstNativeAmount,
            lzTxParams.dstNativeAddr
        );

        (uint256 fee, ) = layerZeroEndpoint.estimateFees(
            dstChainId,
            address(this),
            newPayload,
            lzTxParams.payInZRO,
            adapterParam
        );

        layerZeroEndpoint.send{value: fee}(
            dstChainId,
            // path = remoteAddress + localAddress
            abi.encodePacked(dittoReceiver, address(this)),
            newPayload,
            payable(address(this)),
            lzTxParams.zroPaymentAddress,
            adapterParam
        );
    }

    /// @inheritdoc ILayerZeroLogic
    function layerZeroMulticall(bytes[] calldata data) external {
        if (msg.sender != dittoReceiver) {
            revert LayerZeroLogic_OnlyDittoBridgeReceiverCanCallThisMethod();
        }

        _validateBridgeCall(
            LayerZeroLogic_VaultCannotUseCrossChainLogic.selector
        );

        _multicall(data);
    }

    // =========================
    // Private functions
    // =========================

    /// @dev Constructs the adapter parameters for a transaction based on the provided inputs.
    /// @dev This function is a helper that prepares parameters based on the type of transaction.
    /// There are two types of transactions:
    /// 1) where only `dstGasForCall` is relevant and
    /// 2) where `dstGasForCall`, `dstNativeAmount`, and `dstNativeAddr` are all relevant.
    /// @param dstGasForCall The amount of gas for the call on the destination chain.
    /// @param dstNativeAmount The amount of native token to be sent along with the call on the destination chain.
    /// @param dstNativeAddr The address of the native token on the destination chain.
    /// @return adapterParam The encoded parameters ready to be used in the transaction.
    function _txParamBuilder(
        uint256 dstGasForCall,
        uint256 dstNativeAmount,
        address dstNativeAddr
    ) private pure returns (bytes memory adapterParam) {
        uint16 txType;

        if (dstNativeAmount > 0 && dstNativeAddr != address(0)) {
            txType = 2;

            adapterParam = abi.encodePacked(
                txType,
                dstGasForCall,
                dstNativeAmount,
                dstNativeAddr
            );
        } else {
            txType = 1;
            adapterParam = abi.encodePacked(txType, dstGasForCall);
        }
    }
}

