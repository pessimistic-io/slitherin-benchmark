// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {RemoteDefiiAgent} from "./RemoteDefiiAgent.sol";
import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";
import {Supported2Tokens} from "./Supported2Tokens.sol";
import {LayerZeroRemoteCalls} from "./LayerZeroRemoteCalls.sol";

import {VelodromeUsdcUsdce} from "./optimism_VelodromeUsdcUsdce.sol";
import "./optimism.sol";
import "./arbitrumOne.sol";

contract Agent is
    RemoteDefiiAgent,
    Supported2Tokens,
    LayerZeroRemoteCalls,
    VelodromeUsdcUsdce
{
    constructor()
        Supported2Tokens(AGENT.USDC, AGENT.USDCe)
        LayerZeroRemoteCalls(AGENT.LZ_ENDPOINT, PRINCIPAL.LZ_CHAIN_ID)
        RemoteDefiiAgent(
            AGENT.ONEINCH_ROUTER,
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

contract Principal is
    RemoteDefiiPrincipal,
    Supported2Tokens,
    LayerZeroRemoteCalls
{
    constructor()
        RemoteDefiiPrincipal(
            PRINCIPAL.ONEINCH_ROUTER,
            AGENT.CHAIN_ID,
            PRINCIPAL.USDC,
            "Velodrome Optimism USDC/USDC.e"
        )
        LayerZeroRemoteCalls(PRINCIPAL.LZ_ENDPOINT, AGENT.LZ_CHAIN_ID)
        Supported2Tokens(PRINCIPAL.USDC, PRINCIPAL.USDCe)
    {}
}

