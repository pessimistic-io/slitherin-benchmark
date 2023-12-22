// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXStakePool {
  function balanceOf(address _account) external view returns (uint256);
  function glp() external view returns (address);
  function totalSupply() external view returns (uint256);
}

