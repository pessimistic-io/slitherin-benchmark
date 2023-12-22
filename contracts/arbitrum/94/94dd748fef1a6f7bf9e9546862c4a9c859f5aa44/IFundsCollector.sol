// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFundsCollector {
    function collectFunds(
        address from,
        uint256 id,
        address token,
        uint256 amount
    ) external;
}

