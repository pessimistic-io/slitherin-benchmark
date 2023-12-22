// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISLLP {
  function approve(address _spender, uint256 _amount) external returns (bool);
  function transfer(address _recipient, uint256 _amount) external returns (bool);
  function transferFrom(
    address _sender,
    address _recipient,
    uint256 _amount
  ) external returns (bool);
  function balanceOf(address _account) external view returns (uint256);
  function totalSupply() external view returns (uint256);
}

