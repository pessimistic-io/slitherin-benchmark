// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IPool.sol";

interface ILendingPool is IPool {
    /// @return uint256 totalCollateralBase
    /// @return uint256 totalDebtBase
    /// @return uint256 availableBorrowBase
    /// @return uint256 currentLiquidiationThreshold
    /// @return uint256 loanToValue
    /// @return uint256 healthFactor
    function getAccountData() external view returns (uint256, uint256, uint256, uint256, uint256, uint256);
    
    function supply(
        address assetAddress,
        uint256 amount
    ) external;

    function withdraw(
        address assetAddress,
        uint256 amount
    ) external returns (uint256);

    function borrow(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode
    ) external;

    function borrowAndTransfer(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode,
        address recipientAddress
    ) external;

    function repay(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode
    ) external returns (uint256);
}
