// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

interface IMUSDManager {
    function totalSupply() external view returns (uint256);

    function getDepositOf(address user) external view returns (uint256);

    function getBorrowedOf(address user) external view returns (uint256);

    function isRedemptionProvider(address user) external view returns (bool);
}

