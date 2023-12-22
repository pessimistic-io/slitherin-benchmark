// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IWinnersCircle {
  function closeWeeklyAndAddWinnings(
    uint256 weeklyCloseTimestamp,
    uint256 priceX96,
    uint256 totalWinningsWeight
  ) external payable;
}

