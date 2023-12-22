pragma solidity ^0.8.0;

interface IUniV3Rebalancer {
  // *** EVENTS ***

  event SetUniContracts(address indexed dysonPool, bool indexed value);

  event ClearStuckBalance(uint256 indexed amount, address indexed receiver, uint256 indexed time);

  event RescueToken(address indexed tokenAddress, address indexed sender, uint256 indexed tokens, uint256 time);

  event UpdateThreshold(int24 indexed thresholdMulti);
}

