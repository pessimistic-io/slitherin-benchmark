// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

library DateTime {
    uint256 constant private SECONDS_PER_DAY = 24 * 60 * 60;

    function diffDays(uint256 fromTimestamp, uint256 toTimestamp)
        internal
        pure
        returns (uint256 _days)
    {
        require(fromTimestamp <= toTimestamp, "toTimestamp must be gt or eq to fromTimeStamp");
        _days = (toTimestamp - fromTimestamp) / SECONDS_PER_DAY;
    }
}
