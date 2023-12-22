// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;


interface ILiquidationPool {
    function addDebtToPool(uint256 _amount, uint256 _accruedFees) external;
}

