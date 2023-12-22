// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IStargateReceiver} from "./IStargateReceiver.sol";
import {ILayerZeroReceiver} from "./ILayerZeroReceiver.sol";

import {IVaultFactory} from "./IVaultFactory.sol";
import {IAccessControlLogic} from "./IAccessControlLogic.sol";

import {Ownable} from "./Ownable.sol";

import {TransferHelper} from "./TransferHelper.sol";

/// @title DittoBridgeReceiver
contract DittoBridgeReceiver is Ownable, IStargateReceiver, ILayerZeroReceiver {
    // =========================
    // Constructor
    // =========================

    address public stargateComposer;
    address public layerZeroEndpoint;

    IVaultFactory public immutable vaultFactory;

    constructor(address _vaultFactory, address _owner) {
        vaultFactory = IVaultFactory(_vaultFactory);
        _transferOwnership(_owner);
    }

    // =========================
    // Events
    // =========================

    /// @notice Emits when a cross-chain call reverts
    /// @param vaultAddress: address where the revert occurred
    /// @param reason: message about the cause of the revert
    event DittoBridgeReceiverRevertData(
        address indexed vaultAddress,
        bytes payload,
        bytes reason
    );

    /// @notice Emits when src and dst vault addresses not matching
    /// @param srcVaultAddress: src chain address
    /// @param dstVaultAddress: dst chain address
    event LayerZeroWrongRecipient(
        address srcVaultAddress,
        address dstVaultAddress
    );

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when anyone other than the StargateComposer tries to call lzRecieve
    error DittoBridgeReciever_OnlyLayerZeroEndpointCanCallThisMethod();

    /// @notice Thrown when anyone other than the StargateComposer tries to call sgRecieve
    error DittoBridgeReciever_OnlyStargateComposerCanCallThisMethod();

    // =========================
    // Admin methods
    // =========================

    /// @notice Sets address of the bridges once
    /// @param _stargateComposer: the address of the stargate composer
    /// @param _layerZeroEndpoint: the address of the layerZero endpoint
    /// @dev only callable by contract owner
    function setBridgeContracts(
        address _stargateComposer,
        address _layerZeroEndpoint
    ) external onlyOwner {
        if (stargateComposer == address(0) && layerZeroEndpoint == address(0)) {
            stargateComposer = _stargateComposer;
            layerZeroEndpoint = _layerZeroEndpoint;
        }
    }

    /// @notice Withdraws any tokens from contract
    /// @param token: the address of the token or address(0) if native currency
    /// @dev only callable by contract owner
    function withdrawToken(address token) external onlyOwner {
        if (token == address(0)) {
            TransferHelper.safeTransferNative(
                msg.sender,
                address(this).balance
            );
        } else {
            TransferHelper.safeTransfer(
                token,
                msg.sender,
                TransferHelper.safeGetBalance(token, address(this))
            );
        }
    }

    // =========================
    // Main functions
    // =========================

    struct BridgePayload {
        // params for vault validation and creation
        address srcChainVaultOwner;
        uint256 vaultVersion;
        uint16 srcChainVaultId;
        // calldata for vault call
        bytes payload;
    }

    /// @inheritdoc IStargateReceiver
    function sgReceive(
        uint16,
        bytes memory _srcChainVaultAddress,
        uint256,
        address token,
        uint256 amountLD,
        bytes calldata payload
    ) external payable override {
        address srcChainVaultAddress = _validateSender(
            stargateComposer,
            _srcChainVaultAddress,
            DittoBridgeReciever_OnlyStargateComposerCanCallThisMethod.selector
        );

        BridgePayload calldata stargatePayload = _decodePayload(payload);

        // gets the vault address for the destination chain
        address dstChainVaultAddress = vaultFactory
            .predictDeterministicVaultAddress(
                stargatePayload.srcChainVaultOwner,
                stargatePayload.srcChainVaultId
            );

        // if addresses from src and dst are the same, we can just transfer the tokens
        if (srcChainVaultAddress == dstChainVaultAddress) {
            // if the vault doesn't exist yet, create it
            if (dstChainVaultAddress.code.length == 0) {
                vaultFactory.crossChainDeploy(
                    stargatePayload.srcChainVaultOwner,
                    stargatePayload.vaultVersion,
                    stargatePayload.srcChainVaultId
                );
            }

            // optimistically send tokens to vault address
            // if the vault owner is not eq the creator -> just transfer the tokens
            // (no need to call the vault, cause in this case we cant asure
            // that the src vault has not been compromised)
            TransferHelper.safeTransfer(token, dstChainVaultAddress, amountLD);

            bytes memory callData = stargatePayload.payload;
            assembly ("memory-safe") {
                mstore(add(callData, 36), amountLD)
            }

            (bool success, bytes memory revertReason) = dstChainVaultAddress
                .call(callData);

            // if revert -> emit the reason and stop tx execution
            if (!success) {
                emit DittoBridgeReceiverRevertData(
                    dstChainVaultAddress,
                    stargatePayload.payload,
                    revertReason
                );
            }
        } else {
            // if addresses are different, we need to transfer the tokens to the srcChainVaultOwner
            // Main sg call cannot reach this condition. Only manual execution via `execute` method!
            TransferHelper.safeTransfer(
                token,
                stargatePayload.srcChainVaultOwner,
                amountLD
            );
        }
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        uint16,
        bytes memory _srcChainVaultAddress,
        uint64,
        bytes calldata payload
    ) external override {
        address srcChainVaultAddress = _validateSender(
            layerZeroEndpoint,
            _srcChainVaultAddress,
            DittoBridgeReciever_OnlyLayerZeroEndpointCanCallThisMethod.selector
        );

        BridgePayload calldata layerZeroPayload = _decodePayload(payload);

        // gets the vault address for the destination chain
        address dstChainVaultAddress = vaultFactory
            .predictDeterministicVaultAddress(
                layerZeroPayload.srcChainVaultOwner,
                layerZeroPayload.srcChainVaultId
            );

        // if addresses from src and dst are the same, we can just transfer the tokens
        if (srcChainVaultAddress == dstChainVaultAddress) {
            // if the vault doesn't exist yet, create it
            if (dstChainVaultAddress.code.length == 0) {
                vaultFactory.crossChainDeploy(
                    layerZeroPayload.srcChainVaultOwner,
                    layerZeroPayload.vaultVersion,
                    layerZeroPayload.srcChainVaultId
                );
            }

            (bool success, bytes memory revertReason) = dstChainVaultAddress
                .call(layerZeroPayload.payload);

            // if revert -> emit the reason and stop tx execution
            if (!success) {
                emit DittoBridgeReceiverRevertData(
                    dstChainVaultAddress,
                    layerZeroPayload.payload,
                    revertReason
                );
            }
        } else {
            // if addresses are different, we emit event
            emit LayerZeroWrongRecipient(
                srcChainVaultAddress,
                dstChainVaultAddress
            );
        }
    }

    // =========================
    // Private functions
    // =========================

    /// @dev Validates that the caller is the expected bridge contract and decodes the source chain vault address.
    /// @param bridgeContract The address of the bridge contract expected to be the message sender.
    /// @param _srcChainVaultAddress The encoded address of the source chain vault.
    /// @param errorSelector A bytes4 error code to revert with if validation fails.
    /// @return srcChainVaultAddress The decoded source chain vault address.
    function _validateSender(
        address bridgeContract,
        bytes memory _srcChainVaultAddress,
        bytes4 errorSelector
    ) internal view returns (address srcChainVaultAddress) {
        if (msg.sender != bridgeContract) {
            assembly ("memory-safe") {
                mstore(0, errorSelector)
                revert(0, 4)
            }
        }

        assembly ("memory-safe") {
            srcChainVaultAddress := shr(
                96,
                mload(add(_srcChainVaultAddress, 32))
            )
        }
    }

    /// @dev Decodes the payload to extract the BridgePayload data structure.
    /// @param payload The calldata bytes containing the encoded BridgePayload.
    /// @return bridgePayload The decoded BridgePayload as a calldata pointer.
    function _decodePayload(
        bytes calldata payload
    ) internal pure returns (BridgePayload calldata bridgePayload) {
        assembly ("memory-safe") {
            bridgePayload := payload.offset
        }
    }
}

