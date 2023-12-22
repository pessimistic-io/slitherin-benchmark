// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ILayerZero} from "./ILayerZero.sol";
import {AppStorage, LayerZeroSettings, LibMagpieAggregator} from "./LibMagpieAggregator.sol";
import {LibTransferKey, TransferKey} from "./LibTransferKey.sol";
import {DataTransferInProtocol, DataTransferType} from "./LibCommon.sol";

struct LayerZeroDataTransferInData {
    uint256 gasLimit;
    uint256 fee;
}

error LayerZeroInvalidPayload();
error LayerZeroInvalidSender();
error LayerZeroSequenceHasPayload();

library LibLayerZero {
    event UpdateLayerZeroSettings(address indexed sender, LayerZeroSettings layerZeroSettings);

    function updateSettings(LayerZeroSettings memory layerZeroSettings) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        s.layerZeroSettings = layerZeroSettings;

        emit UpdateLayerZeroSettings(msg.sender, layerZeroSettings);
    }

    event AddLayerZeroChainIds(address indexed sender, uint16[] networkIds, uint16[] chainIds);

    function addLayerZeroChainIds(uint16[] memory networkIds, uint16[] memory chainIds) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        uint256 i;
        uint256 l = networkIds.length;
        for (i = 0; i < l; ) {
            s.layerZeroChainIds[networkIds[i]] = chainIds[i];

            unchecked {
                i++;
            }
        }

        emit AddLayerZeroChainIds(msg.sender, networkIds, chainIds);
    }

    event AddLayerZeroNetworkIds(address indexed sender, uint16[] chainIds, uint16[] networkIds);

    function addLayerZeroNetworkIds(uint16[] memory chainIds, uint16[] memory networkIds) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        uint256 i;
        uint256 l = chainIds.length;
        for (i = 0; i < l; ) {
            s.layerZeroNetworkIds[chainIds[i]] = networkIds[i];

            unchecked {
                i++;
            }
        }

        emit AddLayerZeroNetworkIds(msg.sender, chainIds, networkIds);
    }

    function decodeDataTransferInPayload(
        bytes memory dataTransferInPayload
    ) internal pure returns (LayerZeroDataTransferInData memory dataTransferInData) {
        assembly {
            mstore(dataTransferInData, mload(add(dataTransferInPayload, 32)))
            mstore(add(dataTransferInData, 32), mload(add(dataTransferInPayload, 64)))
        }
    }

    function encodeRemoteAndLocalAddresses(
        bytes32 remoteAddress,
        bytes32 localAddress
    ) private pure returns (bytes memory encodedRemoteAndLocalAddresses) {
        encodedRemoteAndLocalAddresses = new bytes(40);

        assembly {
            mstore(add(encodedRemoteAndLocalAddresses, 32), shl(96, remoteAddress))
            mstore(add(encodedRemoteAndLocalAddresses, 52), shl(96, localAddress))
        }
    }

    function dataTransfer(bytes memory payload, DataTransferInProtocol memory protocol) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        LayerZeroDataTransferInData memory dataTransferInData = decodeDataTransferInPayload(protocol.payload);

        bytes memory adapterParams = hex"00010000000000000000000000000000000000000000000000000000000000000000";

        assembly {
            mstore(add(adapterParams, 34), mload(dataTransferInData))
        }

        ILayerZero(s.layerZeroSettings.routerAddress).send{value: dataTransferInData.fee}(
            s.layerZeroChainIds[protocol.networkId],
            encodeRemoteAndLocalAddresses(
                s.magpieAggregatorAddresses[protocol.networkId],
                bytes32(uint256(uint160(address(this))))
            ),
            payload,
            payable(msg.sender),
            address(0x0),
            adapterParams
        );
    }

    function getPayload(bytes memory dataTransferOutPayload) internal returns (bytes memory extendedPayload) {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        TransferKey memory transferKey = LibTransferKey.decode(dataTransferOutPayload);
        bytes memory srcAddress = encodeRemoteAndLocalAddresses(
            bytes32(uint256(uint160(address(this)))),
            s.magpieAggregatorAddresses[transferKey.networkId]
        );

        ILayerZero layerZero = ILayerZero(s.layerZeroSettings.routerAddress);

        if (layerZero.hasStoredPayload(s.layerZeroChainIds[transferKey.networkId], srcAddress)) {
            layerZero.retryPayload(s.layerZeroChainIds[transferKey.networkId], srcAddress, dataTransferOutPayload);
        }

        if (
            s.payloadHashes[uint16(DataTransferType.LayerZero)][transferKey.networkId][transferKey.senderAddress][
                transferKey.swapSequence
            ] == keccak256(dataTransferOutPayload)
        ) {
            extendedPayload = dataTransferOutPayload;
        } else {
            // Fallback
            extendedPayload = s.payloads[uint16(DataTransferType.LayerZero)][transferKey.networkId][
                transferKey.senderAddress
            ][transferKey.swapSequence];

            if (extendedPayload.length == 0) {
                revert LayerZeroInvalidPayload();
            }
        }
    }

    function registerPayload(TransferKey memory transferKey, bytes memory extendedPayload) private {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        if (
            s.payloadHashes[uint16(DataTransferType.LayerZero)][transferKey.networkId][transferKey.senderAddress][
                transferKey.swapSequence
            ] != bytes32(0)
        ) {
            revert LayerZeroSequenceHasPayload();
        }

        s.payloadHashes[uint16(DataTransferType.LayerZero)][transferKey.networkId][transferKey.senderAddress][
            transferKey.swapSequence
        ] = keccak256(extendedPayload);
    }

    event LzReceive(TransferKey transferKey, bytes payload);

    function lzReceive(
        uint16 senderChainId,
        bytes memory localAndRemoteAddresses,
        bytes memory extendedPayload
    ) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        bytes32 senderAddress;

        assembly {
            senderAddress := shr(96, mload(add(localAndRemoteAddresses, 32)))
        }

        TransferKey memory transferKey = LibTransferKey.decode(extendedPayload);

        LibTransferKey.validate(
            transferKey,
            TransferKey({
                networkId: s.layerZeroNetworkIds[senderChainId],
                senderAddress: senderAddress,
                swapSequence: transferKey.swapSequence
            })
        );

        registerPayload(transferKey, extendedPayload);

        emit LzReceive(transferKey, extendedPayload);
    }

    function enforce() internal view {
        AppStorage storage s = LibMagpieAggregator.getStorage();
        if (msg.sender != s.layerZeroSettings.routerAddress) {
            revert LayerZeroInvalidSender();
        }
    }
}

