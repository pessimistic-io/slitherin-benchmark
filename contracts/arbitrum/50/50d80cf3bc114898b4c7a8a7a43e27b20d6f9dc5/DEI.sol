pragma solidity ^0.8.13;

import "./IERC20.sol";

contract DEI is IERC20 {

  /* 
  #### The only DEI that should ever existed
  ####  
  #### Always transferable 
  #### Not mintable
  #### Not burnable
  #### Not upgradable
  #### Not exploitable
  #### Funny supply

  By: mevfuk
  */

  string public constant symbol = "DEI";
  string public constant name = "DEI";
  uint8 public constant decimals = 18;
  uint public override totalSupply = 0;

  mapping(address => uint) public override balanceOf;
  mapping(address => mapping(address => uint)) public override allowance;
  
  constructor() {
    _mint(msg.sender, 420691337 * 1e18);
  }

  function approve(address _spender, uint _value) external override returns (bool) {
    require(_spender != address(0), "DEI: Approve to the zero address");
    allowance[msg.sender][_spender] = _value;
    emit Approval(msg.sender, _spender, _value);
    return true;
  }

  function _mint(address _to, uint _amount) internal returns (bool) {
    require(_to != address(0), "DEI: Mint to the zero address");
    balanceOf[_to] += _amount;
    totalSupply += _amount;
    emit Transfer(address(0x0), _to, _amount);
    return true;
  }

  function _transfer(address _from, address _to, uint _value) internal returns (bool) {
    require(_to != address(0), "DEI: Transfer to the zero address");

    uint fromBalance = balanceOf[_from];
    require(fromBalance >= _value, "DEI: Transfer amount exceeds balance");
  unchecked {
    balanceOf[_from] = fromBalance - _value;
  }

    balanceOf[_to] += _value;
    emit Transfer(_from, _to, _value);
    return true;
  }

  function transfer(address _to, uint _value) external override returns (bool) {
    return _transfer(msg.sender, _to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) external override returns (bool) {
    address spender = msg.sender;
    uint spenderAllowance = allowance[_from][spender];
    if (spenderAllowance != type(uint).max) {
      require(spenderAllowance >= _value, "DEI: Insufficient allowance");
    unchecked {
      uint newAllowance = spenderAllowance - _value;
      allowance[_from][spender] = newAllowance;
      emit Approval(_from, spender, newAllowance);
    }
    }
    return _transfer(_from, _to, _value);
  }
}

