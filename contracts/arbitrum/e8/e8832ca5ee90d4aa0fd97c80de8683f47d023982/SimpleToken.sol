// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./ERC20.sol";
import "./Ownable.sol";

contract SimpleToken is ERC20, Ownable {
  constructor(string memory _name, string memory _symbol) public ERC20(_name, _symbol) {
    mint(msg.sender, 1000 * 10**18);
  }

  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }

  receive() external payable {
    _mint(msg.sender, msg.value);
  }
}

