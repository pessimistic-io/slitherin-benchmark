// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "./Ownable.sol";

contract WeeklyRebateLimit is Ownable {
    uint256 public weeklyLimit;
    uint256 public cumulativeWeeklyRebates;
    uint256 public weekNum = block.timestamp / 1 weeks;

    event UpdateWeeklyLimit(uint256 limit);

    /// @param _weeklyLimit the initial weekly limit of rebates
    constructor(uint256 _weeklyLimit) {
        weeklyLimit = _weeklyLimit;
        emit UpdateWeeklyLimit(_weeklyLimit);
    }

    /**
     * @dev sets the weekly limit of forex to be distributed
     * @param newLimit the new weekly limit
     */
    function setWeeklyLimit(uint256 newLimit) external onlyOwner {
        require(
            newLimit != weeklyLimit,
            "HpsmRebateHandler: State already set"
        );
        weeklyLimit = newLimit;
        emit UpdateWeeklyLimit(newLimit);
    }

    /**
     * @dev increases the cumulative weekly amount of rebates
     * @param increaseAmount the amount to increase
     */
    function _increaseCumulativeWeeklyRebates(uint256 increaseAmount) internal {
        cumulativeWeeklyRebates += increaseAmount;
    }

    /**
     * @dev returns whether increasing the weekly limit by {rebate} will cause it to be over the
     * weekly limit. Updates the weekly limit if a week has passed.
     * @param rebate the rebate to check
     */
    function _isRebateOverWeeklyLimit(uint256 rebate) internal returns (bool) {
        uint256 currentWeek = block.timestamp / 1 weeks;
        if (currentWeek > weekNum) {
            cumulativeWeeklyRebates = 0;
            weekNum = currentWeek;
        }

        return cumulativeWeeklyRebates + rebate > weeklyLimit;
    }
}

