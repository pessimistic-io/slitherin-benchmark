// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {DelegatedCallType, LibGuard} from "./LibGuard.sol";
import {AppStorage, LayerZeroSettings, WormholeSettings} from "./LibMagpieAggregator.sol";
import {LibDataTransfer} from "./LibDataTransfer.sol";
import {LibLayerZero} from "./LibLayerZero.sol";
import {LibWormhole} from "./LibWormhole.sol";
import {IDataTransfer} from "./IDataTransfer.sol";
import {DataTransferInArgs, DataTransferOutArgs, TransferKey} from "./LibCommon.sol";

contract DataTransferFacet is IDataTransfer {
    AppStorage internal s;

    function updateLayerZeroSettings(LayerZeroSettings calldata layerZeroSettings) external override {
        LibDiamond.enforceIsContractOwner();
        LibLayerZero.updateSettings(layerZeroSettings);
    }

    function addLayerZeroChainIds(uint16[] calldata networkIds, uint16[] calldata chainIds) external override {
        LibDiamond.enforceIsContractOwner();
        LibLayerZero.addLayerZeroChainIds(networkIds, chainIds);
    }

    function addLayerZeroNetworkIds(uint16[] calldata chainIds, uint16[] calldata networkIds) external override {
        LibDiamond.enforceIsContractOwner();
        LibLayerZero.addLayerZeroNetworkIds(chainIds, networkIds);
    }

    function updateWormholeSettings(WormholeSettings calldata wormholeSettings) external override {
        LibDiamond.enforceIsContractOwner();
        LibWormhole.updateSettings(wormholeSettings);
    }

    function addWormholeNetworkIds(uint16[] calldata chainIds, uint16[] calldata networkIds) external override {
        LibDiamond.enforceIsContractOwner();
        LibWormhole.addWormholeNetworkIds(chainIds, networkIds);
    }

    function getWormholeCoreSequence(uint64 transferKeyCoreSequence) external view returns (uint64) {
        return LibWormhole.getCoreSequence(transferKeyCoreSequence);
    }

    function lzReceive(
        uint16 senderChainId,
        bytes calldata localAndRemoteAddresses,
        uint64,
        bytes calldata extendedPayload
    ) external override {
        LibLayerZero.enforce();
        LibLayerZero.lzReceive(senderChainId, localAndRemoteAddresses, extendedPayload);
    }

    function dataTransferIn(DataTransferInArgs calldata dataTransferInArgs) external payable override {
        LibGuard.enforceDelegatedCallGuard(DelegatedCallType.DataTransferIn);
        LibDataTransfer.dataTransfer(dataTransferInArgs);
    }

    function dataTransferOut(DataTransferOutArgs calldata dataTransferOutArgs)
        external
        payable
        override
        returns (TransferKey memory, bytes memory)
    {
        LibGuard.enforceDelegatedCallGuard(DelegatedCallType.DataTransferOut);
        return LibDataTransfer.getPayload(dataTransferOutArgs);
    }
}

