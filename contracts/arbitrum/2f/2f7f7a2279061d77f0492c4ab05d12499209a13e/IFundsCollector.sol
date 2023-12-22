// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IFundsCollector {
    // FundsCollector should collect funds (with transferFrom)
    // and implement logic how send this funds to recipient
    function collectFunds(
        address withdrawalAddress,
        address owner,
        address token,
        uint256 amount
    ) external;
}

