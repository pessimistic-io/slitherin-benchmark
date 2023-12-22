// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./Ownable.sol";

contract TimeChecker is Ownable {
  uint256 private _duration;
  uint256 private minDuration;

  constructor() {
    _duration = 1 days;
    minDuration = 30 minutes;
  }

  modifier timeValid(uint256 time) {
    require(
      time + _duration >= block.timestamp,
      "expired, please send another transaction with new signature"
    );
    _;
  }

  /**
   * @dev Returns the max duration for function called by user
   */
  function getDuration() external view returns (uint256 duration) {
    return _duration;
  }

  /**
   * @dev Change duration value
   */
  function updateDuation(uint256 valNew) external onlyOwner {
    require(valNew > minDuration, "duration too short");
    _duration = valNew;
  }
}

