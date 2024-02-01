// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IWETH {
  function balanceOf(address account) external view returns (uint256);

  function withdraw(uint amount) external;

  function deposit() external payable;

  function transferFrom(address src, address dst, uint wad) external returns (bool);
}

