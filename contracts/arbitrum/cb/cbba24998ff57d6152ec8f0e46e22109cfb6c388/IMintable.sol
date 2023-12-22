// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8;

interface IMintable {
  function isMinter(address _account) external returns (bool);

  function setMinter(address _minter, bool _isActive) external;

  function mint(address _account, uint256 _amount) external;

  function burn(address _account, uint256 _amount) external;
}

