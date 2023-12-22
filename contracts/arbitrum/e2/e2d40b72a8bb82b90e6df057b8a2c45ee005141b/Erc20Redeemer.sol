// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";

import { IRedeemer } from "./IRedeemer.sol";

contract Erc20Redeemer is IRedeemer {
    bool public constant hasPreWithdraw = false;

    function preWithdraw(
        address asset,
        address withdrawer,
        uint portion
    ) external payable override {}

    function withdraw(
        address asset,
        address withdrawer,
        uint portion
    ) external payable {
        uint balance = IERC20(asset).balanceOf(address(this));
        uint amountToRedeem = (balance * portion) / 10 ** 18;
        IERC20(asset).transfer(withdrawer, amountToRedeem);
    }
}

