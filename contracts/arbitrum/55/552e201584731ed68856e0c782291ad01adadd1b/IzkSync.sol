// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IzkSync {
    function withdraw(
        address to,
        address token, 
        uint256 amount
    ) external payable;
}
