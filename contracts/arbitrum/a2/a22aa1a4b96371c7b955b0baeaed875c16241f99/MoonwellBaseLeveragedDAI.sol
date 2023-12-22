// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";
import {RemoteDefiiAgent} from "./RemoteDefiiAgent.sol";
import {Supported2Tokens} from "./Supported2Tokens.sol";
import {Supported3Tokens} from "./Supported3Tokens.sol";

import {RemoteCallsLZ} from "./RemoteCallsLZ.sol";

import "./base.sol";
import "./arbitrumOne.sol";
import "./common.sol";

contract Principal is RemoteDefiiPrincipal, Supported2Tokens, RemoteCallsLZ {
    constructor()
        RemoteDefiiPrincipal(
            common.ONEINCH_ROUTER,
            common.OPERATOR_REGISTRY,
            Base.CHAIN_ID,
            ArbitrumOne.USDC,
            "[USD] Moonwell Base Leveraged DAI"
        )
        Supported2Tokens(ArbitrumOne.USDCe, ArbitrumOne.DAI)
        RemoteCallsLZ(ArbitrumOne.LZ_ENDPOINT, Base.LZ_ID, common.LZ_GAS)
    {}
}

contract Agent is RemoteDefiiAgent, RemoteCallsLZ, Supported3Tokens {
    constructor()
        RemoteDefiiAgent(
            common.ONEINCH_ROUTER,
            common.OPERATOR_REGISTRY,
            ArbitrumOne.CHAIN_ID,
            ExecutionConstructorParams({
                logic: 0x9864D8C3D8c1782393f83D8c0C83aB51d45aDe12,
                incentiveVault: msg.sender,
                treasury: msg.sender,
                fixedFee: 5, // 0.05%
                performanceFee: 1000 // 10%
            })
        )
        Supported3Tokens(Base.DAI, Base.USDbC, Base.USDC)
        RemoteCallsLZ(ArbitrumOne.LZ_ENDPOINT, Base.LZ_ID, common.LZ_GAS)
    {}
}

