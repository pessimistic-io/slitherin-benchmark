// SPDX-License-Identifier: MIT
pragma solidity >=0.8.5 <0.9.0;

import "./ERC20.sol";

contract ERC20Mock is ERC20 {
  /*==================================================== EVENTS ===========================================================*/

  event Mint(address to, uint256 amount);
  event Burn(address to, uint256 amount);

  constructor(string memory name, string memory symbol, uint256 initialSupply, uint8 _decimals) ERC20(name, symbol, _decimals) {
    _mint(msg.sender, initialSupply);
  }

  function mint(address account, uint256 _amount) public {
    _mint(account, _amount);
  }

  function burn(address account, uint256 _amount) public {
    _burn(account, _amount);
  }
}

