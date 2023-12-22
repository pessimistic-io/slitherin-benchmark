// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICamelotLp {
  function getReserves() external view returns(uint112 reserve0, uint112 reserve1, uint16 token0FeePercent, uint16 token1FeePercent);

  function totalSupply() external view returns (uint256);

  function stableSwap() external view returns (bool);

  function token0() external view returns (address);

  function token1() external view returns (address);
}

