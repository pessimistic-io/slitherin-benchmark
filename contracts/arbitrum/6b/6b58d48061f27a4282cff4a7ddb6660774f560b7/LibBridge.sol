// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {AppStorage} from "./LibMagpieAggregator.sol";
import {LibWormhole} from "./LibWormhole.sol";
import {LibStargate} from "./LibStargate.sol";
import {BridgeInArgs, BridgeOutArgs, BridgeType} from "./data-transfer_LibCommon.sol";

error InvalidBridgeType();

library LibBridge {
    function bridgeIn(BridgeInArgs memory bridgeInArgs) internal {
        if (bridgeInArgs.bridgeArgs.bridgeType == BridgeType.Wormhole) {
            LibWormhole.bridgeIn(bridgeInArgs);
        } else if (bridgeInArgs.bridgeArgs.bridgeType == BridgeType.Stargate) {
            LibStargate.bridgeIn(bridgeInArgs);
        } else {
            revert InvalidBridgeType();
        }
    }

    function bridgeOut(BridgeOutArgs memory bridgeOutArgs) internal returns (uint256 amount) {
        if (bridgeOutArgs.bridgeArgs.bridgeType == BridgeType.Wormhole) {
            amount = LibWormhole.bridgeOut(bridgeOutArgs);
        } else if (bridgeOutArgs.bridgeArgs.bridgeType == BridgeType.Stargate) {
            amount = LibStargate.bridgeOut(bridgeOutArgs);
        } else {
            revert InvalidBridgeType();
        }
    }
}

