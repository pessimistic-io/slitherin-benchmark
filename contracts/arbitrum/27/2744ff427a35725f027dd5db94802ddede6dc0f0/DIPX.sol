// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract DIPX is ERC20, ERC20Burnable, Ownable{
  mapping(address => bool) public isMinter;

  constructor() ERC20("DIPX Token","DIPX"){
    _mint(msg.sender, 500_000_000 * 10 ** decimals());
  }

  function setMinter(address _minter, bool _active) public onlyOwner{
    isMinter[_minter] = _active;
  }
  
  function mint(address to, uint256 value) public {
    require(isMinter[msg.sender], "DIPX: caller is not the minter");
    _mint(to, value);
  }
}
