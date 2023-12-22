pragma solidity >= 0.8.0;

interface IInterestRateModel {
    /// @notice calculate interest rate per accrual interval
    /// @param _cash The total pooled amount
    /// @param _utilization The total amount of token reserved as collteral
    /// @return borrow rate per interval, scaled by Constants.PRECISION (1e10)
    function getBorrowRatePerInterval(uint256 _cash, uint256 _utilization) external view returns (uint256);
}

