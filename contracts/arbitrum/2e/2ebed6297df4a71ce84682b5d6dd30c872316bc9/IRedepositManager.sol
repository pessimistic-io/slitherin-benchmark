// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IRedepositManager {
    function redeposit(
        uint32 productId,
        address asset,
        uint128 amount,
        address receiver
    ) external;
}

