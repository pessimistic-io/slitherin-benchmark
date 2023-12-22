// SPDX-License-Identifier: BSD-3-Clause
pragma solidity >=0.6.2;

interface IChainlinkPriceOracle {
  function decimals() external view returns (uint8);
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

