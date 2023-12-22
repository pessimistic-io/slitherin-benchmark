// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

interface IBurnable {
  function balanceOf(address account) external view returns (uint256);

  function burn(uint256 amount) external;

  function burnFrom(address account, uint256 amount) external;
}

