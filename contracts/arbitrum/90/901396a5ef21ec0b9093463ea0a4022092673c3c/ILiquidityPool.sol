//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ILiquidityPool {
    function updatedBorrowBy(address _borrower) external view returns (uint256);
}

