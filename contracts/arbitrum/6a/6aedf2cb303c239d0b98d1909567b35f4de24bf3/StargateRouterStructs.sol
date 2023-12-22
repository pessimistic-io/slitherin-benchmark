// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

struct LayerZeroTxConfig {
    uint256 dstGasForCall;
    uint256 dstNativeAmount;
    bytes dstNativeAddr;
}

