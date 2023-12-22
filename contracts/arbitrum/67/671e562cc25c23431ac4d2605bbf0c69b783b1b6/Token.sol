// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

abstract contract Token {
  string public name;
  string public symbol;
  uint256 public totalSupply;
  uint8 public decimals = 0;

  mapping (address => uint256) private balances;
  mapping (address => mapping(address => uint256)) private allowances;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  constructor(string memory _name, string memory _symbol) {
    name = _name;
    symbol = _symbol;
  }

  function balanceOf(address holder) public view returns (uint256) {
    return balances[holder];
  }

  function allowance(address owner, address spender) public view returns (uint256) {
    return allowances[owner][spender];
  }

  function _transfer(address from, address to, uint256 value, bool withAllowance) internal {
    require(from != address(0), "sender cannot be zero address");
    require(to != address(0), "recipient cannot be zero address");
    require(value <= balances[from], "balance to low");

    if(from != msg.sender && withAllowance) {
      require(allowances[from][msg.sender] >= value, "allowance to low");
      
      unchecked{
        _approve(from, msg.sender, allowances[from][msg.sender] - value);
      }
    }

    unchecked{
      balances[from] -= value;
      balances[to] += value;
    }
    emit Transfer(from, to, value);
  }

  function _approve (address owner, address spender, uint256 value) internal {
    require(owner != address(0), "owner cannot be zero address");
    require(spender != address(0), "spender cannot be zero address");
    
    allowances[owner][spender] = value;
    emit Approval(owner, spender, value);
  }

  function _mint(address to, uint256 value) internal {
    require(to != address(0), "recipient cannot be zero address");

    totalSupply += value;
    unchecked {
      balances[to] += value;
    }
    emit Transfer(address(0), to, value);
  }

  function _burn(address from, uint256 value) internal {
    require(from != address(0), "cannot burn from zero address");
    require(balances[from] >= value, "burn amount exceeds account balance");
    
    unchecked {
      balances[from] -= value;
      totalSupply -= value;
    }
    emit Transfer(from, address(0), value);
  }

}
