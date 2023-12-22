// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOracle {
  /**
   * return amount of tokens that are required to receive that much eth.
   */
  function decimals() external view returns (uint8);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

