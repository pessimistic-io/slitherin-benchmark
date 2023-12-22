// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface IWeth {
  function deposit() external payable;

  function withdraw(uint256 amount) external;

  function withdrawTo(address account, uint256 amount) external;
}

