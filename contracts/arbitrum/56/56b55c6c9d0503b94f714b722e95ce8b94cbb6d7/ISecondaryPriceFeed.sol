// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISecondaryPriceFeed {
  function getPrice(uint64 _pairIndex) external returns (uint256 price);
}
