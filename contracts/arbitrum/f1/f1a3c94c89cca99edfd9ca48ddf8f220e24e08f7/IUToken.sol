//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/**
 *  @title UToken Interface
 *  @dev Union members can borrow and repay thru this component.
 */
interface IUToken {
    /**
     *  @dev Returns the remaining amount that can be borrowed from the market.
     *  @return Remaining total amount
     */
    function getRemainingDebtCeiling() external view returns (uint256);

    /**
     *  @dev Get the borrowed principle
     *  @param account Member address
     *  @return Borrowed amount
     */
    function getBorrowed(address account) external view returns (uint256);

    /**
     *  @dev Get the last repay block
     *  @param account Member address
     *  @return Block number
     */
    function getLastRepay(address account) external view returns (uint256);

    /**
     *  @dev Get member interest index
     *  @param account Member address
     *  @return Interest index
     */
    function getInterestIndex(address account) external view returns (uint256);

    /**
     *  @dev Check if the member's loan is overdue
     *  @param account Member address
     *  @return Check result
     */
    function checkIsOverdue(address account) external view returns (bool);

    /**
     *  @dev Get the borrowing interest rate per block
     *  @return Borrow rate
     */
    function borrowRatePerBlock() external view returns (uint256);

    /**
     *  @dev Get the origination fee
     *  @param amount Amount to be calculated
     *  @return Handling fee
     */
    function calculatingFee(uint256 amount) external view returns (uint256);

    /**
     *  @dev Calculating member's borrowed interest
     *  @param account Member address
     *  @return Interest amount
     */
    function calculatingInterest(address account) external view returns (uint256);

    /**
     *  @dev Get a member's current owed balance, including the principle and interest but without updating the user's states.
     *  @param account Member address
     *  @return Borrowed amount
     */
    function borrowBalanceView(address account) external view returns (uint256);

    /**
     *  @dev Change loan origination fee value
     *  Accept claims only from the admin
     *  @param originationFee_ Fees deducted for each loan transaction
     */
    function setOriginationFee(uint256 originationFee_) external;

    /**
     *  @dev Update the market debt ceiling to a fixed amount, for example, 1 billion DAI etc.
     *  Accept claims only from the admin
     *  @param debtCeiling_ The debt limit for the whole system
     */
    function setDebtCeiling(uint256 debtCeiling_) external;

    /**
     *  @dev Update the max loan size
     *  Accept claims only from the admin
     *  @param maxBorrow_ Max loan amount per user
     */
    function setMaxBorrow(uint256 maxBorrow_) external;

    /**
     *  @dev Update the minimum loan size
     *  Accept claims only from the admin
     *  @param minBorrow_ Minimum loan amount per user
     */
    function setMinBorrow(uint256 minBorrow_) external;

    /**
     *  @dev Change loan overdue duration, based on the number of blocks
     *  Accept claims only from the admin
     *  @param overdueBlocks_ Maximum late repayment block. The number of arrivals is a default
     */
    function setOverdueBlocks(uint256 overdueBlocks_) external;

    /**
     *  @dev Change to a different interest rate model
     *  Accept claims only from the admin
     *  @param newInterestRateModel New interest rate model address
     */
    function setInterestRateModel(address newInterestRateModel) external;

    function setReserveFactor(uint256 reserveFactorMantissa_) external;

    function supplyRatePerBlock() external returns (uint256);

    function accrueInterest() external returns (bool);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function mint(uint256 mintAmount) external;

    function redeem(uint256 redeemTokens) external;

    function redeemUnderlying(uint256 redeemAmount) external;

    function addReserves(uint256 addAmount) external;

    function removeReserves(address receiver, uint256 reduceAmount) external;

    /**
     *  @dev Borrowing from the market
     *  Accept claims only from the member
     *  Borrow amount must in the range of creditLimit, minLoan, debtCeiling and not overdue
     *  @param amount Borrow amount
     */
    function borrow(uint256 amount) external;

    /**
     *  @dev Repay the loan
     *  Accept claims only from the member
     *  Updated member lastPaymentEpoch only when the repayment amount is greater than interest
     *  @param amount Repay amount
     */
    function repayBorrow(uint256 amount) external;

    /**
     *  @dev Repay the loan
     *  Accept claims only from the member
     *  Updated member lastPaymentEpoch only when the repayment amount is greater than interest
     *  @param borrower Borrower address
     *  @param amount Repay amount
     */
    function repayBorrowBehalf(address borrower, uint256 amount) external;

    /**
     *  @dev Update borrower overdue info
     *  @param account Borrower address
     */
    function updateOverdueInfo(address account) external;

    /**
     *  @dev debt write off
     *  @param borrower Borrower address
     *  @param amount WriteOff amount
     */
    function debtWriteOff(address borrower, uint256 amount) external;
}

