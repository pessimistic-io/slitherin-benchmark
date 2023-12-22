// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {ERC20} from "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {LocalDefii} from "./LocalDefii.sol";

contract AaveV3Usdt is LocalDefii {
    // tokens
    IERC20 USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 aArbUSDT = IERC20(0x6ab707Aca953eDAeFBc4fD23bA73294241490620);

    // contracts
    IPool pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    constructor(address swapHelper_) LocalDefii(swapHelper_) {}

    function _enter() internal override {
        uint256 balance = USDT.balanceOf(address(this));
        USDT.approve(address(pool), balance);
        pool.supply(address(USDT), balance, address(this), 0);
    }

    function _exit(uint256 lpAmount) internal override {
        pool.withdraw(address(USDT), lpAmount, address(this));
    }

    function ownedLpAmount() public view override returns (uint256) {
        return aArbUSDT.balanceOf(address(this));
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

