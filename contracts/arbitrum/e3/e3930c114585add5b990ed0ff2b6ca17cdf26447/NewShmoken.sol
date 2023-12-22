pragma solidity 0.8.18;

// SPDX-License-Identifier: MIT

contract NewShmoken {
  string public name = "ShliapaShliapnaya";
  string public symbol = "SHP2";
  uint8 public decimals = 18;
  uint256 public totalSupply = 10;

  mapping (address => uint256) public balances;
  address public owner;

  constructor() {
    owner = msg.sender;
    balances[owner] = totalSupply;
  }

  function transfer(address recipient, uint256 amount) public {
    require(balances[msg.sender] >= amount, "Insufficient balance.");
    balances[msg.sender] -= amount;
    balances[recipient] += amount;
  }
}