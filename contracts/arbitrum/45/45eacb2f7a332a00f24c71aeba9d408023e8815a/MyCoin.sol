pragma solidity 0.8.17;

contract MyCoin {
  string public name = "My Coin";
  string public symbol = "MYC";
  uint8 public decimals = 18;
  uint256 public totalSupply = 1000000000;

  mapping (address => uint256) public balances;
  mapping (address => mapping (address => uint256)) public allowed;
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

  function approve(address spender, uint256 amount) public returns (bool) {
    allowed[msg.sender][spender] = amount;
    return true;
  }

  function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
    require(balances[sender] >= amount, "Insufficient balance.");
    require(allowed[sender][msg.sender] >= amount, "Not allowed to transfer this amount.");
    balances[sender] -= amount;
    balances[recipient] += amount;
    allowed[sender][msg.sender] -= amount;
    return true;
  }
}