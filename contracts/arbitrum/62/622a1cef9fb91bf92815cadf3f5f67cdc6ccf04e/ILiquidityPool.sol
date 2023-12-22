// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

interface ILiquidityPool {
    function updatedBorrowBy(address _borrower) external view returns (uint256);

    function flashLoan(
        address _receiver,
        uint256 _amount,
        bytes memory _params
    ) external;
}

