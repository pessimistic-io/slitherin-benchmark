// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IWNative {
  function deposit() external payable;

  function transfer(address to, uint256 value) external returns (bool);

  function withdraw(uint256) external;

  function mint(address to, uint256 value) external;

  function balanceOf(address wallet) external returns (uint256);
}

