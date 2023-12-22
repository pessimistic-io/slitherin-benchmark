// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasury {
    function fundOracle(address oracle, uint256 amount) external;

    function creditVault() external payable;

    function debitVault(address destination, uint256 amount) external;

    function notifyFeeReceived(address currency, uint256 amount) external;
}

