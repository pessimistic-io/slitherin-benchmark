// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ILendingPoolV2 {
    function withdraw(address asset, uint256 amount, address to) external;
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external;
}

