//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IOptionPricing {
  function getOptionPrice(
    int256 currentPrice,
    uint256 strike,
    int256 volatility,
    int256 amount,
    bool isPut,
    uint256 expiry,
    uint256 epochDuration
  ) external view returns (uint256);
}

