// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DateTime.sol";

contract InvestPeriod {
    uint256 constant day = 24 * 60 * 60;
    uint256 constant weekly = 7 * day;
    uint256 constant monthly = 30 * day;
    uint256 constant quarterly = 3 * monthly;

    function getNextPeriodDate(uint256 investPeriod, uint256 timestamp) public pure returns (uint256) {
        uint startOfToday = timestamp / day * day;
        if (investPeriod == InvestPeriod.weekly) {
            uint dayOfWeek = DateTime.getDayOfWeek(timestamp);
            return DateTime.addDays(startOfToday, 7 - dayOfWeek + 1);
        } else if (investPeriod == InvestPeriod.monthly) {
            (uint year, uint month,) = DateTime.timestampToDate(timestamp);
            uint startOfTheMonth = DateTime.timestampFromDate(year, month, 1);
            return DateTime.addMonths(startOfTheMonth, 1);
        } else if (investPeriod == InvestPeriod.quarterly) {
            (uint year, uint month,) = DateTime.timestampToDate(timestamp);
            uint startOfTheQuater = DateTime.timestampFromDate(year, ((month - 1) / 3 * 3 + 1), 1);
            return DateTime.addMonths(startOfTheQuater, 3);
        } else {
            revert("I/unknown-invest-period");
        }
    }
}
