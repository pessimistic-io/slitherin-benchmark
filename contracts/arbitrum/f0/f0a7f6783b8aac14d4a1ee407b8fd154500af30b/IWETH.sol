// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IWETH {
  function allowance(address src, address guy) external view returns (uint256);

  function approve(address guy, uint256 wad) external returns (bool);

  function balanceOf(address guy) external view returns (uint256);

  function decimals() external view returns (uint8);

  function deposit() external payable;

  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function totalSupply() external;

  function transfer(address dst, uint256 wad) external returns (bool);

  function transferFrom(address src, address dst, uint256 wad) external;

  function withdraw(uint256 wad) external;
}

