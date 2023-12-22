// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {LibBytes} from "./LibBytes.sol";
import {TransferKey} from "./LibTransferKey.sol";
import {Transaction} from "./LibTransaction.sol";

enum BridgeType {
    Wormhole,
    Stargate,
    Celer
}

struct BridgeArgs {
    BridgeType bridgeType;
    bytes payload;
}

struct BridgeInArgs {
    uint16 recipientNetworkId;
    BridgeArgs bridgeArgs;
    uint256 amount;
    address toAssetAddress;
    TransferKey transferKey;
}

struct BridgeOutArgs {
    BridgeArgs bridgeArgs;
    Transaction transaction;
    TransferKey transferKey;
}

struct RefundArgs {
    uint16 recipientNetworkId;
    uint256 amount;
    address toAssetAddress;
    TransferKey transferKey;
    BridgeArgs bridgeArgs;
    bytes payload;
}

