// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IInterestRateModel.sol";

contract NormalInterestRateModel is Ownable, IInterestRateModel {
    bool public constant IS_INTEREST_RATE_MODEL = true;

    uint256 private constant BASE = 1e18;

    /**
     * @notice Number of seconds per year
     */
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint256 public multiplierPerSec;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint256 public baseRatePerSec;

    event NewInterestParams(uint256 baseRatePerSec, uint256 multiplierPerSec);

    /**
     * @notice Construct an interest rate model
     * @param _baseRatePerYear The approximate target base APR, as a mantissa (scaled by BASE)
     * @param _multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by BASE)
     */
    constructor(uint256 _baseRatePerYear, uint256 _multiplierPerYear) {
        updateParams(_baseRatePerYear, _multiplierPerYear);
    }

    function isInterestRateModel() public pure returns (bool) {
        return IS_INTEREST_RATE_MODEL;
    }

    function updateParams(
        uint256 _baseRatePerYear,
        uint256 _multiplierPerYear
    ) public onlyOwner {
        baseRatePerSec = _baseRatePerYear / SECONDS_PER_YEAR;
        multiplierPerSec = _multiplierPerYear / SECONDS_PER_YEAR;

        emit NewInterestParams(baseRatePerSec, multiplierPerSec);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param _cash The amount of cash in the market
     * @param _borrows The amount of borrows in the market
     * @param _reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, BASE]
     */
    function utilizationRate(uint256 _cash, uint256 _borrows, uint256 _reserves) public pure returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (_borrows == 0) {
            return 0;
        }

        return (_borrows * BASE) / (_cash + _borrows - _reserves);
    }

    /**
     * @notice Calculates the current borrow rate per sec, with the error code expected by the market
     * @param _cash The amount of cash in the market
     * @param _borrows The amount of borrows in the market
     * @param _reserves The amount of reserves in the market
     * @return The borrow rate percentage per sec as a mantissa (scaled by BASE)
     */
    function getBorrowRate(uint256 _cash, uint256 _borrows, uint256 _reserves) public view override returns (uint256) {
        uint256 ur = utilizationRate(_cash, _borrows, _reserves);
        return ((ur * multiplierPerSec) / BASE) + baseRatePerSec;
    }

    /**
     * @notice Calculates the current supply rate per sec
     * @param _cash The amount of cash in the market
     * @param _borrows The amount of borrows in the market
     * @param _reserves The amount of reserves in the market
     * @param _reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per sec as a mantissa (scaled by BASE)
     */
    function getSupplyRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves,
        uint256 _reserveFactorMantissa
    ) public view override returns (uint256) {
        uint256 oneMinusReserveFactor = BASE - _reserveFactorMantissa;
        uint256 borrowRate = getBorrowRate(_cash, _borrows, _reserves);
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / BASE;
        return (utilizationRate(_cash, _borrows, _reserves) * rateToPool) / BASE;
    }
}
