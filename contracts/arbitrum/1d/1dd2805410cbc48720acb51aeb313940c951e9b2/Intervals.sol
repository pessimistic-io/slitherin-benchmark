// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

library Intervals {

  function regularYearInSeconds() internal pure returns(uint256) {
    return 365 * 1 days;
  }

  function leapYearInSeconds() internal pure returns(uint256) {
    return 366 * 1 days;
  }
  
  function intervalLongerThanFourHours(uint256 _startInterval, uint256 _endInterval) internal pure returns(bool) {
    return (_endInterval - _startInterval) >= 4 hours;
  }

  function intervalLongerThanOneDay(uint256 _startInterval, uint256 _endInterval) internal pure returns(bool) {
    return (_endInterval - _startInterval) >= 1 days;
  }

  function numberOfIntervalFromTime(uint256 _time, uint256 _interval) internal pure returns(uint256) {
    return _time / _interval;
  }

  function secondsLeftFromTimeForInterval(uint256 _time, uint256 _interval) internal pure returns(uint256) {
    return _time % _interval;
  }
  
  function getNbOfIntervalsAndSecondsLeft(uint256 _time, uint256 _interval) internal pure returns(uint256, uint256) {
    uint256 _secondsLeft = secondsLeftFromTimeForInterval(_time, _interval);
    uint256 _nbOfIntervals = 0;
    if(_time >= _interval) {
      _nbOfIntervals = numberOfIntervalFromTime(_time, _interval);
    }
    return (_nbOfIntervals, _secondsLeft);
  }
}
