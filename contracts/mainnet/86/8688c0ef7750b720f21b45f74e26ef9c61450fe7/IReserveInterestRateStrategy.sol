pragma solidity ^0.5.0;

/**
* IReserveInterestRateStrategyInterface interface
* -
* Interface for the calculation of the interest rates.
* -
* This contract was cloned from Populous and modified to work with the Populous World eco-system.
**/

interface IReserveInterestRateStrategy {

    /**
    * @dev returns the base variable borrow rate, in rays
    */

    function getBaseVariableBorrowRate() external view returns (uint256);
    /**
    * @dev calculates the liquidity, stable, and variable rates depending on the current utilization rate
    *      and the base parameters
    *
    */
    function calculateInterestRates(
        address _reserve,
        uint256 _utilizationRate,
        uint256 _totalBorrowsStable,
        uint256 _totalBorrowsVariable,
        uint256 _averageStableBorrowRate)
    external
    view
    returns (uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate);
}

