// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface ILendable {
    function receiveBorrow(
        address borrower,
        uint256 borrowAmount
    ) external;

    function processRepay(
        address repayer,
        uint256 repayAmount
    ) external payable;
}

