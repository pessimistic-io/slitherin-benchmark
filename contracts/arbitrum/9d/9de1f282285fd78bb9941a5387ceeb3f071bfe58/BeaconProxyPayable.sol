// SPDX-License-Identifier: UNLICENSED

// Copyright (c) Flora - All rights reserved
// https://twitter.com/Flora_Loans

pragma solidity 0.8.19;

import "./BeaconProxy.sol";

contract BeaconProxyPayable is BeaconProxy {
    receive() external payable override {
        // Only from the WETH contract
        require(
            /// note: ALWAYS UPDATE ON DEPLOYMENT
            msg.sender == 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, //Arbitrum WETH
            "LendingPair: not WETH"
        );
    }

    constructor(
        address beacon,
        bytes memory data
    ) payable BeaconProxy(beacon, data) {}
}

