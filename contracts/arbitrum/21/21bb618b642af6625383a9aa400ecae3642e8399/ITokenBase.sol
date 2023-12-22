// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITokenBase {
    /**
     * @notice Event emitted when interest is accrued
     */
    event AccrueInterest(uint256 cashPrior, uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows);

    /**
     * @notice Event emitted when tokens are minted
     */
    event Supply(address supplier, uint256 supplyAmount, uint256 tokensMinted);

    /**
     * @notice Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    /**
     * @notice Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows);

    /**
     * @notice Event emitted when a borrow is repaid
     */
    event RepayBorrow(
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 accountBorrows,
        uint256 totalBorrows
    );

    /**
     * @notice Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(address liquidator, address borrower, uint256 repayAmount, address fTokenCollateral);

    event LiquidationProtected(bytes32 _id, address _borrower, address _liquidator);

    event TokenSeized(address from, address to, uint256 amount);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);

    /*** Admin Events ***/

    /**
     * @notice Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @notice Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    event NewReserveFactor(uint256 oldReserveFactor, uint256 newReserveFactor);

    event NewPriceOracle(address oldOracle, address newOracle);

    function isFToken() external view returns (bool);

    function balanceOfUnderlying(address _account) external returns (uint256);

    function getAccountSnapshot(address _account) external view returns (uint256, uint256, uint256);

    function getLastAccrualTime() external view returns (uint256);

    function getRiskManager() external view returns (address);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function totalBorrowsCurrent() external view returns (uint256);

    function borrowBalanceCurrent(address _account) external view returns (uint256);

    function exchangeRateCurrent() external view returns (uint256);

    function seize(address _liquidator, address _borrower, uint256 _seizeTokens) external;

    /*** Admin ***/
    function setPendingAdmin(address newPendingAdmin) external;

    function acceptAdmin() external;
}
