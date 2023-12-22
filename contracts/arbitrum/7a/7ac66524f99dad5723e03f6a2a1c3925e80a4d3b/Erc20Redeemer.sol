// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { VaultBaseExternal } from "./VaultBaseExternal.sol";

import { IRedeemer } from "./IRedeemer.sol";
import { Constants } from "./Constants.sol";

contract Erc20Redeemer is IRedeemer {
    bool public constant hasPreWithdraw = false;

    function preWithdraw(
        uint tokenId,
        address asset,
        address withdrawer,
        uint portion
    ) external payable override {}

    function withdraw(
        uint tokenId,
        address asset,
        address withdrawer,
        uint portion
    ) external payable {
        uint balance = IERC20(asset).balanceOf(address(this));
        uint amountToRedeem = (balance * portion) / Constants.PORTION_DIVISOR;
        IERC20(asset).transfer(withdrawer, amountToRedeem);
        VaultBaseExternal(address(this)).registry().emitEvent();
        emit Redeemed(tokenId, asset, withdrawer, asset, amountToRedeem);
    }
}

