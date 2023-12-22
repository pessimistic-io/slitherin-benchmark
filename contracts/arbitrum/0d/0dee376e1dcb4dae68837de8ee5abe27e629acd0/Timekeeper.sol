// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.6;

import "./BokkyPooBahsDateTimeLibrary.sol";

interface ITimekeeper {
    function isTradingOpen(address _pair) external view returns (bool);
}

contract Timekeeper is ITimekeeper {
    event Log(string str);

    int256 constant EARLY_OFFSET = 14;
    int256 constant LATE_OFFSET = -12;

    struct pairTimekeeper {
        uint8 openingHour;
        uint8 openingMinute;
        uint8 closingHour;
        uint8 closingMinute;
        uint8[7] closedDays; // if 1 : closed, if 0 : open
        int8 utcOffset;
        bool isOnlyDay;
    }
    mapping(address => pairTimekeeper) public TimekeeperPerLp;
    mapping(address => pairTimekeeper) public TimekeeperPerLpWaitingForApproval;

    mapping(address => bool) public isForceOpen;
    mapping(address => bool) public isForceOpenTimelock;

    constructor() public {}

    function isTradingOpen(
        address _pair
    ) public view virtual override returns (bool) {
        uint256 blockTime = block.timestamp;
        return isTradingOpenAt(blockTime, _pair);
    }

    function isTradingOpenAt(
        uint256 timestamp,
        address _pair
    ) public view returns (bool) {
        if (!isForceOpen[_pair]) {
            uint256 localTimeStamp = applyOffset(timestamp, _pair);

            uint day = BokkyPooBahsDateTimeLibrary.getDayOfWeek(localTimeStamp);

            if (TimekeeperPerLp[_pair].closedDays[day - 1] == 1) {
                return false;
            }

            uint256 now_hour;
            uint256 now_minute;

            if (!TimekeeperPerLp[_pair].isOnlyDay) {
                (, , , now_hour, now_minute, ) = BokkyPooBahsDateTimeLibrary
                    .timestampToDateTime(localTimeStamp);

                return isOpeningHour(now_hour, now_minute, _pair);
            } else return true;
        } else return true;
    }

    function applyOffset(
        uint256 timestamp,
        address _pair
    ) internal view returns (uint256) {
        uint256 localTimeStamp;
        if (TimekeeperPerLp[_pair].utcOffset >= 0) {
            localTimeStamp = BokkyPooBahsDateTimeLibrary.addHours(
                timestamp,
                uint256(TimekeeperPerLp[_pair].utcOffset)
            );
        } else {
            localTimeStamp = BokkyPooBahsDateTimeLibrary.subHours(
                timestamp,
                uint256(-TimekeeperPerLp[_pair].utcOffset)
            );
        }
        return localTimeStamp;
    }

    function isOpeningHour(
        uint256 hour,
        uint256 minute,
        address _pair
    ) internal view returns (bool) {
        uint256 openingHour = TimekeeperPerLp[_pair].openingHour;
        uint256 closingHour = TimekeeperPerLp[_pair].closingHour;
        uint256 openingMinute = TimekeeperPerLp[_pair].openingMinute;
        uint256 closingMinute = TimekeeperPerLp[_pair].closingMinute;

        if (
            openingHour < closingHour ||
            (openingHour == closingHour && openingMinute < closingMinute)
        ) {
            if (hour < openingHour || hour > closingHour) {
                return false;
            }
            if (hour == openingHour && minute < openingMinute) {
                return false;
            }
            if (hour == closingHour && minute >= closingMinute) {
                return false;
            }
        } else if (
            openingHour == closingHour && openingMinute == closingMinute
        ) {
            return false; // if both hours and minutes are same, then it's not open at any time
        } else {
            // this block handles the case when the business opens on one day and closes on the next
            // dont understand
            if (hour < openingHour && hour > closingHour) {
                return false;
            }
            if (hour == openingHour && minute < openingMinute) {
                return false;
            }
            if (hour == closingHour && minute >= closingMinute) {
                return false;
            }
        }

        return true;
    }

    function _setUTCOffset(int8 utcOffset, address _pair) internal {
        require(utcOffset < EARLY_OFFSET, "Invalid UCT offset");
        require(utcOffset > LATE_OFFSET, "Invalid UCT offset");
        TimekeeperPerLpWaitingForApproval[_pair].utcOffset = utcOffset;
    }

    function _setClosingDays(
        uint8[7] memory ClosedDays,
        address _pair
    ) internal {
        for (uint256 i = 0; i < ClosedDays.length; i++) {
            require(ClosedDays[i] == 0 || ClosedDays[i] == 1);
        }
        TimekeeperPerLpWaitingForApproval[_pair].closedDays = ClosedDays;
    }


    function _setHoursAndMinutes( uint8 openingHour,uint8 closingHour,uint8 openingMinute, uint8 closingMin, address _pair) internal {
        require(0 <= openingHour && openingHour <= 23, " invalid Opening hour");
        require(0 <= closingHour && closingHour <= 23, " invalid Closing hour");
        require(0 <= openingMinute && openingMinute <= 59," invalid Opening minutes");
        require(0 <= closingMin && closingMin <= 59," invalid Closing minutes");

        require(openingHour < closingHour || (openingHour == closingHour && openingMinute < closingMin)," invalid logic for time");

        TimekeeperPerLpWaitingForApproval[_pair].openingHour = openingHour;
        TimekeeperPerLpWaitingForApproval[_pair].closingHour = closingHour;

        TimekeeperPerLpWaitingForApproval[_pair].openingMinute = openingMinute;
        TimekeeperPerLpWaitingForApproval[_pair].closingMinute = closingMin;
    }

    function _setKeeperGlobal(
        address _pair,
        uint8 openingHour,
        uint8 openingMinute,
        uint8 closingHour,
        uint8 closingMin,
        uint8[7] memory ClosedDays,
        int8 utcOffset,
        bool onlyDay
    ) internal {
        delete TimekeeperPerLpWaitingForApproval[_pair];
        _setHoursAndMinutes(openingHour, closingHour, openingMinute, closingMin, _pair);
        _setClosingDays(ClosedDays, _pair);
        _setUTCOffset(utcOffset, _pair);
        _setIsOnlyDays(onlyDay, _pair);
    }


    function _setIsOnlyDays(bool isOnlyDay, address _pair) internal {
        TimekeeperPerLpWaitingForApproval[_pair].isOnlyDay = isOnlyDay;
    }
}

