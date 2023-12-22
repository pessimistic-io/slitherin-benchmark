// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./IERC20.sol";
/**
 * Types for the eHXRO contracts
 */

struct InboundPayload {
    bytes32 solToken;
    uint256 amount;
    bytes messageHash;
}

enum Bridge {
    WORMHOLE,
    MAYAN_SWAP,
    VERY_REAL_BRIDGE
}

struct BridgeResult {
    Bridge id;
    bytes trackableHash;
}

error NotSigOwner();

error UnsupportedToken();

error InvalidNonce();

error BridgeFailed(bytes revertReason);

