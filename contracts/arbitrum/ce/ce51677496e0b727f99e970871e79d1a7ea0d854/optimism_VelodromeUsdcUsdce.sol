// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {IRouter} from "./IRouter.sol";
import {IGauge} from "./IGauge.sol";

import {Execution} from "./Execution.sol";

import "./optimism.sol";

abstract contract VelodromeUsdcUsdce is Execution {
    // tokens
    IERC20 VELO = IERC20(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
    IERC20 lpToken = IERC20(0x36E3c209B373b861c185ecdBb8b2EbDD98587BDb);

    // contracts
    IRouter router = IRouter(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    IGauge gauge = IGauge(0x6dd083cEe9638E0827Dc86805C9891c493f34C56);

    constructor() {
        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(USDCe).approve(address(router), type(uint256).max);
        lpToken.approve(address(router), type(uint256).max);
        lpToken.approve(address(gauge), type(uint256).max);
    }

    function _enterLogic() internal override {
        (, , uint256 lpAmount) = router.addLiquidity(
            USDC,
            USDCe,
            true,
            IERC20(USDC).balanceOf(address(this)),
            IERC20(USDCe).balanceOf(address(this)),
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
            USDC,
            USDCe,
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
        VELO.transfer(INCENTIVE_VAULT, VELO.balanceOf(address(this)));
    }

    function _withdrawLiquidityLogic(
        address to,
        uint256 liquidity
    ) internal override {
        gauge.withdraw(liquidity);
        lpToken.transfer(to, liquidity);
    }
}

