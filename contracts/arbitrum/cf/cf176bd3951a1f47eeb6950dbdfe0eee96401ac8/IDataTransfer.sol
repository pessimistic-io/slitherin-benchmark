// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LayerZeroSettings, WormholeSettings} from "./LibMagpieAggregator.sol";
import {DataTransferInArgs, DataTransferOutArgs, TransferKey} from "./LibCommon.sol";

interface IDataTransfer {
    event UpdateLayerZeroSettings(address indexed sender, LayerZeroSettings layerZeroSettings);

    function updateLayerZeroSettings(LayerZeroSettings calldata layerZeroSettings) external;

    event AddLayerZeroChainIds(address indexed sender, uint16[] networkIds, uint16[] chainIds);

    function addLayerZeroChainIds(uint16[] calldata networkIds, uint16[] calldata chainIds) external;

    event AddLayerZeroNetworkIds(address indexed sender, uint16[] chainIds, uint16[] networkIds);

    function addLayerZeroNetworkIds(uint16[] calldata chainIds, uint16[] calldata networkIds) external;

    event UpdateWormholeSettings(address indexed sender, WormholeSettings wormholeSettings);

    function updateWormholeSettings(WormholeSettings calldata wormholeSettings) external;

    event AddWormholeNetworkIds(address indexed sender, uint16[] chainIds, uint16[] networkIds);

    function addWormholeNetworkIds(uint16[] calldata chainIds, uint16[] calldata networkIds) external;

    function getWormholeCoreSequence(uint64 transferKeyCoreSequence) external view returns (uint64);

    event LzReceive(TransferKey transferKey, bytes payload);

    function lzReceive(
        uint16 senderChainId,
        bytes calldata senderAddress,
        uint64 nonce,
        bytes calldata extendedPayload
    ) external;

    function dataTransferIn(DataTransferInArgs calldata dataTransferInArgs) external payable;

    function dataTransferOut(
        DataTransferOutArgs calldata dataTransferOutArgs
    ) external payable returns (TransferKey memory, bytes memory);
}

