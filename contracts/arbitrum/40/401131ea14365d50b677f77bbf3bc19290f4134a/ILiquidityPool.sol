// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

interface ILiquidityPool {
    function updatedBorrowBy(address _borrower) external view returns (uint256);

    function borrow(uint256 _amount) external;

    function repay(uint256 _amount) external;

    function whitelistRepay(uint256 _amount) external;

    function flashLoan(
        address _receiver,
        uint256 _amount,
        bytes memory _params
    ) external;

    function getFlashLoanFeeFactor() external view returns (uint256);
}

