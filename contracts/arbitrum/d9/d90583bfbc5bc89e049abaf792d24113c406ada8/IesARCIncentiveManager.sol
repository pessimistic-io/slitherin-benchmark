// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

interface IesARCIncentiveManager {
    function registerALPDeposit(address _provider, uint256 _amountUSDT, uint256 _timestamp, uint256 _amountALP) external;
    function registerALPWithdrawal(address _provider, uint256 _amountUSDT, uint256 _timestamp, uint256 _amountALP) external;
}

