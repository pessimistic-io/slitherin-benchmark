// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILevelARBOracle {
  function getLLPPrice(address _token, bool _bool) external view returns (uint256);
  function getLLPAmountIn(
    uint256 _amtOut,
    address _tokenIn,
    address _tokenOut
  ) external view returns (uint256);
}

