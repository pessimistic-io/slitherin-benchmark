// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {RemoteDefiiAgent} from "./RemoteDefiiAgent.sol";
import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";
import {Supported2Tokens} from "./Supported2Tokens.sol";
import {RemoteCallsLZ} from "./RemoteCallsLZ.sol";

import {VelodromeUsdcUsdce} from "./optimism_VelodromeUsdcUsdce.sol";
import "./optimism.sol";
import "./arbitrumOne.sol";

contract Agent is
    RemoteDefiiAgent,
    Supported2Tokens,
    RemoteCallsLZ,
    VelodromeUsdcUsdce
{
    constructor()
        Supported2Tokens(AGENT.USDC, AGENT.USDCe)
        RemoteCallsLZ(AGENT.LZ_ENDPOINT, PRINCIPAL.LZ_CHAIN_ID)
        RemoteDefiiAgent(
            AGENT.ONEINCH_ROUTER,
            AGENT.OPERATOR_REGISTRY,
            PRINCIPAL.CHAIN_ID,
            ExecutionConstructorParams({
                incentiveVault: msg.sender,
                treasury: msg.sender,
                fixedFee: 50, // 0.5%
                performanceFee: 2000 // 20%
            })
        )
    {}
}

contract Principal is RemoteDefiiPrincipal, Supported2Tokens, RemoteCallsLZ {
    constructor()
        RemoteDefiiPrincipal(
            PRINCIPAL.ONEINCH_ROUTER,
            PRINCIPAL.OPERATOR_REGISTRY,
            AGENT.CHAIN_ID,
            PRINCIPAL.USDC,
            "Velodrome Optimism USDC/USDC.e"
        )
        RemoteCallsLZ(PRINCIPAL.LZ_ENDPOINT, AGENT.LZ_CHAIN_ID)
        Supported2Tokens(PRINCIPAL.USDC, PRINCIPAL.USDCe)
    {}
}

