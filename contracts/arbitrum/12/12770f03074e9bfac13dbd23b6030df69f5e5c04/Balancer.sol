// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== Balancer.sol ==============================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./IStabilizer.sol";
import "./PRBMathSD59x18.sol";
import "./TransferHelper.sol";
import "./Owned.sol";
import "./IERC20.sol";

contract Balancer is Owned {
    using PRBMathSD59x18 for int256;

    // Constants
    uint256 private constant DAY_TIMESTAMP = 24 * 60 * 60;
    int256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant PRECISE_PRICE_PRECISION = 1e18;
    uint256 private constant TIME_ONE_YEAR = 365 * 24 * 60 * 60;

    IERC20 public USDX;

    // Events
    event InterestRateRefreshed(int256 interestRate);

    constructor(
        address _sweep_address,
        address _usdc_address
    ) Owned(_sweep_address) {
        USDX = IERC20(_usdc_address);
    }

    /**
     * @notice refresh interest rate weekly.
     */
    function refreshInterestRate() public onlyAdmin {
        int256 interest_rate = SWEEP.interest_rate();
        uint256 amm_price = SWEEP.amm_price();
        uint256 current_target_price = SWEEP.target_price();
        uint256 period_time = SWEEP.period_time();
        int256 step_value = SWEEP.step_value();

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
    function getNextTargetPrice(uint256 _current_target_price, int256 _interest_rate, uint256 _period_time) internal pure returns (uint256) {
        int256 year = int256(TIME_ONE_YEAR).fromInt();
        int256 period = int256(_period_time).fromInt();
        int256 time_ratio = period.div(year);
        int256 price_ratio = PRICE_PRECISION + _interest_rate;
        int256 price_unit = price_ratio.pow(time_ratio).div(
            PRICE_PRECISION.pow(time_ratio)
        );

        return (_current_target_price * uint256(price_unit)) / PRECISE_PRICE_PRECISION;
    }

    function marginCalls(
        address[] memory _targets,
        uint256[] memory _percentages,
        uint256 sweep_to_peg
    ) external onlyAdmin {
        require(_targets.length == _percentages.length, "Wrong data received");
        uint len = _targets.length;

        for(uint index = 0; index < len; ) {
            uint256 amount = (sweep_to_peg * _percentages[index]) / 1e6;
            IStabilizer(_targets[index]).marginCall(amount);
            unchecked { ++index; }
        }
    }
}
