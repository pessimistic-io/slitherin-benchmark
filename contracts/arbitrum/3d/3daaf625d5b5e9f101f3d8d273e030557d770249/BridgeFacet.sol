// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {IMessageBus} from "./IMessageBus.sol";
import {DelegatedCallType, LibGuard} from "./LibGuard.sol";
import {AppStorage, WormholeSettings, WormholeBridgeSettings, StargateSettings, CelerBridgeSettings} from "./LibMagpieAggregator.sol";
import {LibGuard} from "./LibGuard.sol";
import {LibPauser} from "./LibPauser.sol";
import {LibBridge} from "./LibBridge.sol";
import {BridgeInArgs, BridgeOutArgs, RefundArgs} from "./data-transfer_LibCommon.sol";
import {LibStargate} from "./LibStargate.sol";
import {LibWormhole} from "./LibWormhole.sol";
import {LibCeler} from "./LibCeler.sol";
import {IBridge} from "./IBridge.sol";

contract BridgeFacet is IBridge {
    AppStorage internal s;

    function updateStargateSettings(StargateSettings calldata stargateSettings) external {
        LibDiamond.enforceIsContractOwner();
        LibStargate.updateSettings(stargateSettings);
    }

    function updateWormholeBridgeSettings(WormholeBridgeSettings calldata wormholeBridgeSettings) external {
        LibDiamond.enforceIsContractOwner();
        LibWormhole.updateSettings(wormholeBridgeSettings);
    }

    function updateCelerBridgeSettings(CelerBridgeSettings calldata celerBridgeSettings) external override {
        LibDiamond.enforceIsContractOwner();
        LibCeler.updateSettings(celerBridgeSettings);
    }

    function addCelerChainIds(uint16[] calldata networkIds, uint64[] calldata chainIds) external override {
        LibDiamond.enforceIsContractOwner();
        LibCeler.addCelerChainIds(networkIds, chainIds);
    }

    function getWormholeTokenSequence(uint64 tokenSequence) external view returns (uint64) {
        return LibWormhole.getTokenSequence(tokenSequence);
    }

    function addMagpieStargateBridgeAddresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieStargateBridgeAddresses
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibStargate.addMagpieStargateBridgeAddresses(networkIds, magpieStargateBridgeAddresses);
    }

    function addMagpieStargateBridgeV2Addresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieStargateBridgeAddresses
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibStargate.addMagpieStargateBridgeV2Addresses(networkIds, magpieStargateBridgeAddresses);
    }

    function addMagpieCelerBridgeAddresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieCelerBridgeAddresses
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibCeler.addMagpieCelerBridgeAddresses(networkIds, magpieCelerBridgeAddresses);
    }

    function bridgeIn(BridgeInArgs calldata bridgeInArgs) external payable override {
        LibGuard.enforceDelegatedCallGuard(DelegatedCallType.BridgeIn);
        LibBridge.bridgeIn(bridgeInArgs);
    }

    function bridgeOut(BridgeOutArgs calldata bridgeOutArgs) external payable override returns (uint256 amount) {
        LibGuard.enforceDelegatedCallGuard(DelegatedCallType.BridgeOut);
        amount = LibBridge.bridgeOut(bridgeOutArgs);
    }
}

