// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

interface IWeth {
  function deposit() external payable;

  function withdraw(uint256 _amount) external;

  function withdrawTo(address account, uint256 amount) external;
}

