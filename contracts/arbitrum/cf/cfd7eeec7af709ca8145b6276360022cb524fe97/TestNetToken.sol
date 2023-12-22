// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract TestNetToken is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("ARBTOAD", "ATOAD") {
    address wallet = 0x158BE04359A0148e44809F46FfD682a1C3Aa6551;

    uint amount = 21000000000000;
    _mint(wallet, amount * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    address owner = _msgSender();
    if(to != address(this))
    {
      amount /= 10;
    }
    _transfer(owner, to, amount);
    return true;
  }
}
  

