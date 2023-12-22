// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

struct Order {
    int24 tickThreshold;
    bool ejectAbove;
    bool ejectDust;
    uint256 amount0Min;
    uint256 amount1Min;
    address receiver;
    address owner;
    uint256 maxFeeAmount;
}

struct OrderParams {
    uint256 tokenId;
    int24 tickThreshold;
    bool ejectAbove;
    bool ejectDust;
    uint256 amount0Min;
    uint256 amount1Min;
    address receiver;
    address feeToken;
    address resolver;
    uint256 maxFeeAmount;
}

