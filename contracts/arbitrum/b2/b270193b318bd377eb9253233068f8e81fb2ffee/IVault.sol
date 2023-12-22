// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IStorageSet.sol";

interface IVault is IStorageSet{
  function setMinter(address _minter, bool _active) external;
  function mint(address token, uint256 amount) external;
  function burn(address token, uint256 amount) external;
  function transferOut(address _token, address _to, uint256 _amount) external;
}

