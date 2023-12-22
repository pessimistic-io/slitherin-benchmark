// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.5;

import "./IPool.sol";

interface IWombatRouter {
  function swapExactTokensForTokens(
    address[] calldata tokenPath,
    address[] calldata poolPath,
    uint256 fromAmount,
    uint256 minimumToAmount,
    address to,
    uint256 deadline
  ) external returns (uint256 amountOut);

  function getAmountOut(
    address[] calldata tokenPath,
    address[] calldata poolPath,
    int256 amountIn
  ) external view returns (uint256 amountOut, uint256[] memory haircuts);

  function getAmountIn(
    address[] calldata tokenPath,
    address[] calldata poolPath,
    uint256 amountOut
  ) external view returns (uint256 amountIn, uint256[] memory haircuts);
}

