// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {ILayerZero} from "./ILayerZero.sol";
import {AppStorage, LayerZeroSettings, LibMagpieAggregator} from "./LibMagpieAggregator.sol";
import {LibTransferKey, TransferKey} from "./LibTransferKey.sol";
import {DataTransferInProtocol, DataTransferType} from "./LibCommon.sol";

struct LayerZeroDataTransferInData {
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

    function decodeDataTransferInPayload(bytes memory dataTransferInPayload)
        internal
        pure
        returns (LayerZeroDataTransferInData memory dataTransferInData)
    {
        assembly {
            mstore(dataTransferInData, mload(add(dataTransferInPayload, 32)))
        }
    }

    function encodeRemoteAndLocalAddresses(bytes32 remoteAddress, address localAddress)
        private
        pure
        returns (bytes memory encodedRemoteAndLocalAddresses)
    {
        encodedRemoteAndLocalAddresses = new bytes(40);

        assembly {
            mstore(add(encodedRemoteAndLocalAddresses, 32), shl(96, remoteAddress))
            mstore(add(encodedRemoteAndLocalAddresses, 52), shl(96, localAddress))
        }
    }

    function dataTransfer(bytes memory payload, DataTransferInProtocol memory protocol) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        LayerZeroDataTransferInData memory dataTransferInData = decodeDataTransferInPayload(protocol.payload);

        ILayerZero(s.layerZeroSettings.routerAddress).send{value: dataTransferInData.fee}(
            s.layerZeroChainIds[protocol.networkId],
            encodeRemoteAndLocalAddresses(s.magpieAggregatorAddresses[protocol.networkId], address(this)),
            payload,
            payable(msg.sender),
            address(0x0),
            hex"00010000000000000000000000000000000000000000000000000000000000030d40"
        );
    }

    function getPayload(bytes memory dataTransferOutPayload) internal view returns (bytes memory extendedPayload) {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        TransferKey memory transferKey = LibTransferKey.decode(dataTransferOutPayload);

        extendedPayload = s.payloads[uint16(DataTransferType.LayerZero)][transferKey.networkId][
            transferKey.senderAddress
        ][transferKey.swapSequence];

        if (extendedPayload.length == 0) {
            revert LayerZeroInvalidPayload();
        }
    }

    function registerPayload(TransferKey memory transferKey, bytes memory extendedPayload) private {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        if (
            s
            .payloads[uint16(DataTransferType.LayerZero)][transferKey.networkId][transferKey.senderAddress][
                transferKey.swapSequence
            ].length > 0
        ) {
            revert LayerZeroSequenceHasPayload();
        }

        s.payloads[uint16(DataTransferType.LayerZero)][transferKey.networkId][transferKey.senderAddress][
                transferKey.swapSequence
            ] = extendedPayload;
    }

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
    }

    function enforce() internal view {
        AppStorage storage s = LibMagpieAggregator.getStorage();
        if (msg.sender != s.layerZeroSettings.routerAddress) {
            revert LayerZeroInvalidSender();
        }
    }
}

