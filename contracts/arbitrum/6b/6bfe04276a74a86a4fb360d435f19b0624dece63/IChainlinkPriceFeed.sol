// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IChainlinkPriceFeed{
  function getBtcUsdPrice() external view returns (int256,uint8);
  function getEthUsdPrice() external view returns (int256,uint8);
  function getPrice(address token) external view returns (int256,uint8);
}
