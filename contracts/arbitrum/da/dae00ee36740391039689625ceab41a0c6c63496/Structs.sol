// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeERC20.sol";

using SafeERC20 for IERC20;

struct BridgeInfo {
    string bridge;
    address dstToken;
    uint64 chainId;
    uint256 amount;
    address user;
    uint64 nonce;
}

struct CBridgeDescription {
    address srcToken;
    uint256 amount;
    address receiver;
    uint64 dstChainId;
    uint64 nonce;
    uint32 maxSlippage;
    address toDstToken;
}

struct SwapData {
    address user;
    address srcToken;
    address dstToken;
    uint256 amount;
    bytes callData;
}

struct MultiChainDescription {
    address srcToken;
    uint256 amount;
    address receiver;
    uint64 dstChainId;
    uint64 nonce;
    address router;
    address toDstToken;
}

struct PolyBridgeDescription {
    address fromAsset;
    uint64 toChainId;
    bytes toAddress;
    uint256 amount;
    uint256 fee;
    uint256 id;
    uint64 nonce;
    address toDstToken;
}

struct PortalBridgeDescription {
    address token;
    uint256 amount;
    uint16 recipientChain;
    address recipient;
    uint32 nonce;
    uint256 arbiterFee;
    bytes payload;
    address toDstToken;
}

struct AnyMapping {
    address tokenAddress;
    address anyTokenAddress;
}

