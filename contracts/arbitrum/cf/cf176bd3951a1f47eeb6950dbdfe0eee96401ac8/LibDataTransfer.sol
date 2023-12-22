// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibBytes} from "./LibBytes.sol";
import {AppStorage, LibMagpieAggregator} from "./LibMagpieAggregator.sol";
import {LibTransferKey, TransferKey} from "./LibTransferKey.sol";
import {LibLayerZero} from "./LibLayerZero.sol";
import {LibWormhole} from "./LibWormhole.sol";
import {DataTransferInArgs, DataTransferOutArgs, DataTransferType} from "./LibCommon.sol";

error InvalidDataTransferType();

library LibDataTransfer {
    using LibBytes for bytes;

    function getOriginalPayload(bytes memory extendedPayload) private pure returns (bytes memory) {
        return extendedPayload.slice(42, extendedPayload.length - 42);
    }

    function dataTransfer(DataTransferInArgs memory dataTransferInArgs) internal {
        bytes memory extendedPayload = LibTransferKey.encode(dataTransferInArgs.transferKey).concat(
            dataTransferInArgs.payload
        );

        if (dataTransferInArgs.protocol.dataTransferType == DataTransferType.Wormhole) {
            LibWormhole.dataTransfer(extendedPayload);
        } else if (dataTransferInArgs.protocol.dataTransferType == DataTransferType.LayerZero) {
            LibLayerZero.dataTransfer(extendedPayload, dataTransferInArgs.protocol);
        } else {
            revert InvalidDataTransferType();
        }
    }

    function getPayload(
        DataTransferOutArgs memory dataTransferOutArgs
    ) internal returns (TransferKey memory transferKey, bytes memory payload) {
        if (dataTransferOutArgs.dataTransferType == DataTransferType.Wormhole) {
            payload = LibWormhole.getPayload(dataTransferOutArgs.payload);
        } else if (dataTransferOutArgs.dataTransferType == DataTransferType.LayerZero) {
            payload = LibLayerZero.getPayload(dataTransferOutArgs.payload);
        } else {
            revert InvalidDataTransferType();
        }

        transferKey = LibTransferKey.decode(payload);
        payload = getOriginalPayload(payload);
    }
}

