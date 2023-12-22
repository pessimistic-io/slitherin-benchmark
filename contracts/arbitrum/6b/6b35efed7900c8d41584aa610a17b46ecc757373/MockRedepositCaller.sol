// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {     IRedepositManager } from "./IRedepositManager.sol";
import { ITreasury } from "./ITreasury.sol";

contract MockRedepositCaller {
    function redeposit(
        IRedepositManager target,
        ITreasury treasury,
        uint32 productId,
        address asset,
        uint128 amount,
        address receiver
    ) external {
        target.redeposit(treasury, productId, asset, amount, receiver);
    }

    function getStrategyOfProduct(uint32) external pure returns (uint32) {
        return 1;
    }

    function dcsAddToDepositQueue(uint32, uint128, address) external payable {}

    function dcsGetProductDepositAsset(uint32) external pure returns (address) {
        return address(0);
    }
}

