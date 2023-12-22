// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {LocalDefii} from "./LocalDefii.sol";
import {Supported2Tokens} from "./Supported2Tokens.sol";

import "./arbitrumOne.sol";

contract ConvexFinance2pool is LocalDefii, Supported2Tokens {
    // contracts
    StableSwap constant stableSwap =
        StableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
    Booster constant booster =
        Booster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ConvexRewardPool constant cvx2CRV =
        ConvexRewardPool(0x971E732B5c91A59AEa8aa5B0c763E6d648362CF8);

    uint256 constant BOOSTER_PID = 7;

    constructor()
        Supported2Tokens(USDCe, USDT)
        LocalDefii(ONEINCH_ROUTER, USDC, "Convex Arbitrum 2pool")
    {
        IERC20(USDCe).approve(address(stableSwap), type(uint256).max);
        IERC20(USDT).approve(address(stableSwap), type(uint256).max);
        stableSwap.approve(address(booster), type(uint256).max);
    }

    function totalLiquidity() public view override returns (uint256) {
        return cvx2CRV.balanceOf(address(this));
    }

    function _enterLogic() internal override {
        uint256 lpAmount = stableSwap.add_liquidity(
            [
                IERC20(USDCe).balanceOf(address(this)),
                IERC20(USDT).balanceOf(address(this))
            ],
            0
        );
        booster.deposit(BOOSTER_PID, lpAmount);
    }

    function _exitLogic(uint256 liquidity) internal override {
        cvx2CRV.withdraw(liquidity, false);
        stableSwap.remove_liquidity(
            stableSwap.balanceOf(address(this)),
            [uint256(0), uint256(0)]
        );
    }

    function _returnUnusedFunds(address recipient) internal override {
        _returnFunds(msg.sender, recipient, USDCe, 0);
        _returnFunds(msg.sender, recipient, USDT, 0);
    }
}

interface StableSwap is IERC20 {
    function add_liquidity(
        uint256[2] memory _amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);

    function remove_liquidity(
        uint256 _burn_amount,
        uint256[2] memory _min_amounts
    ) external returns (uint256[2] memory);
}

interface Booster {
    function deposit(uint256 _pid, uint256 _amount) external returns (bool);

    function balanceOf(address arrg0) external view returns (uint256);
}

interface ConvexRewardPool is IERC20 {
    function withdraw(uint256 _amount, bool _claim) external returns (bool);
}

