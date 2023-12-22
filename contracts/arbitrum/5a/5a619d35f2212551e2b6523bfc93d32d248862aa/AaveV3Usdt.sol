// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {RemoteDefiiAgent} from "./RemoteDefiiAgent.sol";
import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";
import {Supported1Token} from "./Supported1Token.sol";
import {LayerZero} from "./LayerZero.sol";

import "./avalanche.sol";
import "./arbitrumOne.sol";

contract AaveV3UsdtAgent is RemoteDefiiAgent, Supported1Token, LayerZero {
    // tokens
    IERC20 constant aAvaUSDT =
        IERC20(0x6ab707Aca953eDAeFBc4fD23bA73294241490620);

    // contracts
    IPool constant pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    constructor()
        Supported1Token(AGENT.USDT)
        LayerZero(AGENT.LZ_ENDPOINT, PRINCIPAL.LZ_CHAIN_ID)
        RemoteDefiiAgent(AGENT.ONEINCH_ROUTER, PRINCIPAL.CHAIN_ID, AGENT.USDC)
    {
        IERC20(AGENT.USDT).approve(address(pool), type(uint256).max);
    }

    function _enterLogic() internal override {
        pool.supply(
            AGENT.USDT,
            IERC20(AGENT.USDT).balanceOf(address(this)),
            address(this),
            0
        );
    }

    function _exitLogic(uint256 lpAmount) internal override {
        pool.withdraw(AGENT.USDT, lpAmount, address(this));
    }

    function totalLiquidity() public view override returns (uint256) {
        return aAvaUSDT.balanceOf(address(this));
    }
}

contract AaveV3UsdtPrincipal is
    RemoteDefiiPrincipal,
    Supported1Token,
    LayerZero
{
    constructor()
        RemoteDefiiPrincipal(
            PRINCIPAL.ONEINCH_ROUTER,
            AGENT.CHAIN_ID,
            PRINCIPAL.USDC,
            "Aave V3 Avalanche USDT"
        )
        LayerZero(PRINCIPAL.LZ_ENDPOINT, AGENT.LZ_CHAIN_ID)
        Supported1Token(PRINCIPAL.USDT)
    {}
}

interface IPool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

