// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

interface ILiquidityPool {
    function flashLoan(
        address _receiver,
        uint256 _amount,
        bytes memory _params
    ) external;

    function liquidate(address _borrower, uint256 _amount) external;

    function liquidateWithPreference(
        address _borrower,
        uint256 _amount,
        address[] memory _markets
    ) external;

    function updatedBorrowBy(address _borrower) external view returns (uint256);

    function whitelistRepay(uint256 _amount) external;

    function addFlashBorrower(address _borrower) external;
}

