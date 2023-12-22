// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {LibDiamond} from "./LibDiamond.sol";
import {AppStorage, WormholeSettings, WormholeBridgeSettings, StargateSettings} from "./LibMagpieAggregator.sol";
import {LibBridge} from "./LibBridge.sol";
import {BridgeInArgs, BridgeOutArgs} from "./data-transfer_LibCommon.sol";
import {LibStargate} from "./LibStargate.sol";
import {LibWormhole} from "./LibWormhole.sol";
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

    function addMagpieStargateBridgeAddresses(
        uint16[] calldata networkIds,
        bytes32[] calldata magpieStargateBridgeAddresses
    ) external override {
        LibDiamond.enforceIsContractOwner();
        LibStargate.addMagpieStargateBridgeAddresses(networkIds, magpieStargateBridgeAddresses);
    }

    function getWormholeTokenSequence(uint64 tokenSequence) external view returns (uint64) {
        return LibWormhole.getTokenSequence(tokenSequence);
    }

    function bridgeIn(BridgeInArgs calldata bridgeInArgs) external payable override {
        LibBridge.bridgeIn(bridgeInArgs);
    }

    function bridgeOut(BridgeOutArgs calldata bridgeOutArgs) external payable override returns (uint256 amount) {
        amount = LibBridge.bridgeOut(bridgeOutArgs);
    }
}

