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

  function getLiquidityForAmount1(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint256 amount1
  ) external pure returns (uint128);

  function getLiquidity(address _dysonStrategy)
  external
  view
  returns (uint256 _a0Expect, uint256 _a1Expect);
}

