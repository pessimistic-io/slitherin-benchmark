// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage} from "./LibMagpieAggregator.sol";
import {TransferKey} from "./LibTransferKey.sol";
import {LibWormhole} from "./LibWormhole.sol";
import {LibStargate} from "./LibStargate.sol";
import {LibCeler} from "./LibCeler.sol";
import {BridgeInArgs, BridgeOutArgs, BridgeType, RefundArgs} from "./data-transfer_LibCommon.sol";

error InvalidBridgeType();

library LibBridge {
    function bridgeIn(BridgeInArgs memory bridgeInArgs) internal {
        if (bridgeInArgs.bridgeArgs.bridgeType == BridgeType.Wormhole) {
            LibWormhole.bridgeIn(bridgeInArgs);
        } else if (bridgeInArgs.bridgeArgs.bridgeType == BridgeType.Stargate) {
            LibStargate.bridgeIn(bridgeInArgs);
        } else if (bridgeInArgs.bridgeArgs.bridgeType == BridgeType.Celer) {
            LibCeler.bridgeIn(bridgeInArgs);
        } else {
            revert InvalidBridgeType();
        }
    }

    function bridgeOut(BridgeOutArgs memory bridgeOutArgs) internal returns (uint256 amount) {
        if (bridgeOutArgs.bridgeArgs.bridgeType == BridgeType.Wormhole) {
            amount = LibWormhole.bridgeOut(bridgeOutArgs);
        } else if (bridgeOutArgs.bridgeArgs.bridgeType == BridgeType.Stargate) {
            amount = LibStargate.bridgeOut(bridgeOutArgs);
        } else if (bridgeOutArgs.bridgeArgs.bridgeType == BridgeType.Celer) {
            amount = LibCeler.bridgeOut(bridgeOutArgs);
        } else {
            revert InvalidBridgeType();
        }
    }
}

