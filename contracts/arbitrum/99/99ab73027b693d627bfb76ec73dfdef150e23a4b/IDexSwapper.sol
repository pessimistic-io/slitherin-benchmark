// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

interface IDexSwapper {
  function swap(
    address tokenIn,
    uint256 inAmount,
    address tokenOut,
    uint256 outMin,
    uint24 poolFee // 0 for Uniswap V2 pools
  ) external;

  function getPoolInfo(
    address targetToken,
    address pool
  )
    external
    view
    returns (
      uint24 poolFee, // The pool's fee in hundredths of a bip, i.e. 1e-6, so 0.3% == 0.003 == 3000
      address token0,
      address token1,
      uint256 reserves0,
      uint256 reserves1,
      uint256 priceX96,
      uint256 priceUSDNoDecimalsX128
    );
}

