// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ILendingPoolV3 {
    function withdraw(address asset, uint256 amount, address to) external;
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 refCode) external;
    function borrow(address asset, uint256 amount, uint256 rateMode, uint16 refCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
}

