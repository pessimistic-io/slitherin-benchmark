// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IFirstTypeNestedStrategies {
    function deposit(address user_, address token_, address vaultAddress_, uint256 amount_, address nodesContract_) external returns (uint256 sharesAmount);
    function withdraw(address user_, address tokenOut_, address vaultAddress_, uint256 sharesAmount_, address nodesContract_) external returns (uint256 amountTokenDesired);
}
