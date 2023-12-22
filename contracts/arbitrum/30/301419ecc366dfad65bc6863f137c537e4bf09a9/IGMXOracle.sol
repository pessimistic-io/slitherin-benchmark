// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXOracle {
  function getGlpAmountIn(
    uint256 _amtOut,
    address _tokenIn,
    address _tokenOut
  ) external view returns (uint256);
}

