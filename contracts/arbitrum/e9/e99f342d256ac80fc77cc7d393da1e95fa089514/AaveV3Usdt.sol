// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {RemoteDefiiAgent} from "./RemoteDefiiAgent.sol";
import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";

import {Supported1Token} from "./Supported1Token.sol";
import {Supported2Tokens} from "./Supported2Tokens.sol";
import {LayerZeroRemoteCalls} from "./LayerZeroRemoteCalls.sol";

import "./avalanche.sol";
import "./arbitrumOne.sol";

contract AaveV3UsdtAgent is
    RemoteDefiiAgent,
    Supported2Tokens,
    LayerZeroRemoteCalls
{
    // tokens
    IERC20 constant aAvaUSDT =
        IERC20(0x6ab707Aca953eDAeFBc4fD23bA73294241490620);

    // contracts
    IPool constant pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    constructor()
        Supported2Tokens(AGENT.USDT, AGENT.USDC)
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

    function _claimRewardsLogic() internal override {
        payable(address(0)).transfer(0); // to suppress warning
        revert();
    }

    function _withdrawLiquidityLogic(
        address to,
        uint256 liquidity
    ) internal override {
        aAvaUSDT.transfer(to, liquidity);
    }
}

contract AaveV3UsdtPrincipal is
    RemoteDefiiPrincipal,
    Supported1Token,
    LayerZeroRemoteCalls
{
    constructor()
        RemoteDefiiPrincipal(
            PRINCIPAL.ONEINCH_ROUTER,
            AGENT.CHAIN_ID,
            PRINCIPAL.USDC,
            "Aave V3 Avalanche USDT"
        )
        LayerZeroRemoteCalls(PRINCIPAL.LZ_ENDPOINT, AGENT.LZ_CHAIN_ID)
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

