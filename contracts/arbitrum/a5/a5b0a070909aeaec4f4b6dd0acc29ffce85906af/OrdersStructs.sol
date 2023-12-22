// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

    struct OrderParams {
        uint16 dstChainId;
        address collectionAddress;
        uint256 amountInBatch;
        uint256 tokenAmount;
        uint16 srcPoolId; // Stargate Pool ID e.g. 1 = USDC
        uint16 dstPoolId;
        address to;
        uint expiration;
        uint256 gas;
    }

