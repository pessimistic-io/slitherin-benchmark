// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {LocalDefii} from "./LocalDefii.sol";
import {Supported1Token} from "./Supported1Token.sol";

import "./arbitrumOne.sol";

contract AaveV3Usdt is Supported1Token, LocalDefii {
    // tokens
    IERC20 aArbUSDT = IERC20(0x6ab707Aca953eDAeFBc4fD23bA73294241490620);

    // contracts
    IPool pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    constructor()
        Supported1Token(USDT)
        LocalDefii(ONEINCH_ROUTER, USDC, "Aave V3 Arbitrum USDT")
    {
        IERC20(USDT).approve(address(pool), type(uint256).max);
    }

    function totalLiquidity() public view override returns (uint256) {
        return aArbUSDT.balanceOf(address(this));
    }

    function _enterLogic() internal override {
        pool.supply(
            USDT,
            IERC20(USDT).balanceOf(address(this)),
            address(this),
            0
        );
    }

    function _exitLogic(uint256 liquidity) internal override {
        pool.withdraw(USDT, liquidity, address(this));
    }

    function _returnUnusedFunds(address recipient) internal override {
        // we use all funds (all token balance) in enter
    }
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

