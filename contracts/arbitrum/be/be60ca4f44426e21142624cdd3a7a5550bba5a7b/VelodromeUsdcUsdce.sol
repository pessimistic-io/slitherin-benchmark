// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {RemoteDefiiAgent} from "./RemoteDefiiAgent.sol";
import {RemoteDefiiPrincipal} from "./RemoteDefiiPrincipal.sol";
import {Supported2Tokens} from "./Supported2Tokens.sol";
import {LayerZero} from "./LayerZero.sol";

import "./optimism.sol";
import "./arbitrumOne.sol";

contract VelodromeUsdcUsdceAgent is
    RemoteDefiiAgent,
    Supported2Tokens,
    LayerZero
{
    // tokens
    IERC20 VELO = IERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    IERC20 lpToken = IERC20(0x36E3c209B373b861c185ecdBb8b2EbDD98587BDb);

    // contracts
    IRouter router = IRouter(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    IGauge gauge = IGauge(0x6dd083cEe9638E0827Dc86805C9891c493f34C56);

    constructor()
        Supported2Tokens(AGENT.USDC, AGENT.USDCe)
        LayerZero(AGENT.LZ_ENDPOINT, PRINCIPAL.LZ_CHAIN_ID)
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
        IERC20(AGENT.USDC).approve(address(router), type(uint256).max);
        IERC20(AGENT.USDCe).approve(address(router), type(uint256).max);
        lpToken.approve(address(router), type(uint256).max);

        lpToken.approve(address(gauge), type(uint256).max);
    }

    function _enterLogic() internal override {
        (, , uint256 lpAmount) = router.addLiquidity(
            AGENT.USDC,
            AGENT.USDCe,
            true,
            IERC20(AGENT.USDC).balanceOf(address(this)),
            IERC20(AGENT.USDCe).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );
        gauge.deposit(lpAmount);
    }

    function _exitLogic(uint256 lpAmount) internal override {
        gauge.withdraw(lpAmount);
        router.removeLiquidity(
            AGENT.USDC,
            AGENT.USDCe,
            true,
            lpAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function totalLiquidity() public view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function _claimRewardsLogic() internal override {
        gauge.getReward(address(this));
        VELO.transfer(incentiveVault, VELO.balanceOf(address(this)));
    }
}

contract VelodromeUsdcUsdcePrincipal is
    RemoteDefiiPrincipal,
    Supported2Tokens,
    LayerZero
{
    constructor()
        RemoteDefiiPrincipal(
            PRINCIPAL.ONEINCH_ROUTER,
            AGENT.CHAIN_ID,
            PRINCIPAL.USDC,
            "Velodrome Optimism USDC/USDC.e"
        )
        LayerZero(PRINCIPAL.LZ_ENDPOINT, AGENT.LZ_CHAIN_ID)
        Supported2Tokens(PRINCIPAL.USDC, PRINCIPAL.USDCe)
    {}
}

interface IRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IGauge {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function balanceOf(address) external view returns (uint256);

    function getReward(address _account) external;
}

