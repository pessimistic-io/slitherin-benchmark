// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.18;

import "./IERC20.sol";

interface IWETH is IERC20 {
  function balanceOf(address account) external view override returns (uint256);

  function deposit() external payable;

  function withdraw(uint256) external;

  function approve(address guy, uint256 wad) external override returns (bool);

  function transferFrom(
    address src,
    address dst,
    uint256 wad
  ) external override returns (bool);

  function transfer(address to, uint value) external override returns (bool);
}

