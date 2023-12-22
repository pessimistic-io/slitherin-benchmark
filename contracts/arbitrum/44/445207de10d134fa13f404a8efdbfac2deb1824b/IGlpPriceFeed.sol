// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IGlpPriceFeed {
  function getPrice(bool maximise) external view returns (uint256 price);

  function convertToUSD(
    uint256 amount,
    bool maximise
  ) external view returns (uint256);

  function convertToGLP(
    address asset,
    uint256 amount,
    bool maximise
  ) external view returns (uint256);
}

