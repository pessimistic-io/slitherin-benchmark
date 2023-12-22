// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IPythPriceFeed{
  function getBtcUsdPrice() external view returns (int256,uint32);
  function getEthUsdPrice() external view returns (int256,uint32);
  function getPrice(address _token) external view returns (int256,uint32);
  function updatePriceFeeds(bytes[] memory _priceUpdateData) external payable;
}
