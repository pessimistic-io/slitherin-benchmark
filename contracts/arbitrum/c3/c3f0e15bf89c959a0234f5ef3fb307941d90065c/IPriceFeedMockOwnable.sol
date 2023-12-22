// SPDX-License-Identifier: MIT
pragma solidity >=0.8.5 <0.9.0;

interface IPriceFeedMockOwnable {
  function getPrice(
    address _token, 
    bool _maximise,
    bool _includeAmmPrice, 
    bool _useSwapPricing) external view returns (uint256);
}

