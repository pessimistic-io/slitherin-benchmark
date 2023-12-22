// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== Balancer.sol ==============================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./IStabilizer.sol";
import "./ISweep.sol";
import "./PRBMathSD59x18.sol";
import "./TransferHelper.sol";
import "./Owned.sol";
import "./IERC20.sol";

contract Balancer is Owned {
    using PRBMathSD59x18 for int256;

    ISweep public SWEEP;

    // Constants
    uint256 private constant DAY_TIMESTAMP = 24 * 60 * 60;
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant PRECISE_PRICE_PRECISION = 1e18;
    uint256 private constant TIME_ONE_YEAR = 365 * 24 * 60 * 60;

    // Events
    event InterestRateRefreshed(uint256 interestRate);

    constructor(
        address _owner_address,
        address _sweep_address
    ) Owned(_owner_address) {
        SWEEP = ISweep(_sweep_address); // Sweep
    }

    /**
     * @notice refresh interest rate weekly.
     */
    function refreshInterestRate() public onlyOwner {
        uint256 interest_rate = SWEEP.interest_rate();
        uint256 amm_price = SWEEP.amm_price();
        uint256 current_target_price = SWEEP.target_price();
        uint256 period_time = SWEEP.period_time();
        uint256 step_value = SWEEP.step_value();
        
        if (amm_price > current_target_price) {
            interest_rate -= step_value;
        } else {
            interest_rate += step_value;
        }

        uint256 next_target_price = getNextTargetPrice(current_target_price, interest_rate, period_time);

        SWEEP.startNewPeriod();
        SWEEP.setInterestRate(interest_rate);
        SWEEP.setTargetPrice(current_target_price, next_target_price);

        emit InterestRateRefreshed(interest_rate);
    }

    /* get next target price with the following formula:  
        next_price = p * (1 + r) ^ (t / y)
        * r: interest rate per year
        * t: time period to pay the rate
        * y: time in one year
        * p: current price
    */
    function getNextTargetPrice(uint256 _current_target_price, uint256 _interest_rate, uint256 _period_time) internal pure returns (uint256) {
        int256 year = int256(TIME_ONE_YEAR).fromInt();
        int256 period = int256(_period_time).fromInt();
        int256 time_ratio = period.div(year);
        int256 price_ratio = int256(PRICE_PRECISION + _interest_rate).fromInt();
        int256 base_precision = int256(PRICE_PRECISION).fromInt();
        int256 price_unit = price_ratio.pow(time_ratio).div(
            base_precision.pow(time_ratio)
        );

        if (_interest_rate > 0) {
            return (_current_target_price * uint256(price_unit)) / PRECISE_PRICE_PRECISION;
        } else {
            return _current_target_price;
        }
    }

    /**
     * @notice Set loan limit of stabilizer.
     * @param stabilizer Address to cancel the request.
     * @param _loan_limit new max mint amount.
     */
    function setLoanLimit(address stabilizer, uint256 _loan_limit) public onlyOwner {
        require(stabilizer != address(0), "Zero address detected.");
        IStabilizer stb = IStabilizer(stabilizer);
        stb.setLoanLimit(_loan_limit);
    }

    /**
     * @notice Set default date.
     * @param stabilizer Address to cancel the request.
     * @param _days_from_now amount of days from now.
     */
    function setDefaultDate(address stabilizer, uint32 _days_from_now) external onlyOwner {
        require(stabilizer != address(0), "Zero address detected.");
        IStabilizer stb = IStabilizer(stabilizer);
        stb.setRepaymentDate(_days_from_now);
    }
}

