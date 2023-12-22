pragma solidity ^0.8.0;

interface IUniswapCalculator {
  /**
   * @dev get price from tick
   */
  function getSqrtRatio(int24 tick) external pure returns (uint160);

  /**
   * @dev get tick from price
   */
  function getTickFromPrice(uint160 price) external pure returns (int24);
}

