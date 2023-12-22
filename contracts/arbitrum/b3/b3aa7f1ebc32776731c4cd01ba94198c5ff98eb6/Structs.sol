// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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
}

struct SwapData {
    address swapRouter;
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
}

struct PolyBridgeDescription {
    address fromAsset;
    uint64 toChainId;
    bytes toAddress;
    uint256 amount;
    uint256 fee;
    uint256 id;
    uint64 nonce;
}

struct PortalBridgeDescription {
    address token;
    uint256 amount;
    uint16 recipientChain;
    address recipient;
    uint32 nonce;
    uint256 arbiterFee;
    bytes payload;
}

struct AnyMapping {
    address tokenAddress;
    address anyTokenAddress;
}

