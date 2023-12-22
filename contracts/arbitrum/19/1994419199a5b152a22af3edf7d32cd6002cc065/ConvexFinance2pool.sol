// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {LocalDefii} from "./LocalDefii.sol";
import {Supported2Tokens} from "./Supported2Tokens.sol";
import {ConvexFinance2pool} from "./arbitrumOne_ConvexFinance2pool.sol";

import "./arbitrumOne.sol";

contract Local is LocalDefii, Supported2Tokens, ConvexFinance2pool {
    constructor()
        Supported2Tokens(USDCe, USDT)
        LocalDefii(
            ONEINCH_ROUTER,
            USDC,
            "Convex Arbitrum 2pool",
            ExecutionConstructorParams({
                incentiveVault: msg.sender,
                treasury: msg.sender,
                fixedFee: 50, // 0.5%
                performanceFee: 2000 // 20%
            })
        )
    {}
}

