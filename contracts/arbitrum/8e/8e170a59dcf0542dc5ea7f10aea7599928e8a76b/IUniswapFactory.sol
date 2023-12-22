// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IUniswapFactory {
  function getPool(address _token0, address _token1, uint24 _fee) external view returns (address);
}
