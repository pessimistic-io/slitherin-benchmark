// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

contract MockERC20 is ERC20Upgradeable, OwnableUpgradeable {
  receive() external payable {
    _mint(msg.sender, msg.value);
  }

  function initialize(string memory _name, string memory _symbol) public initializer {
    OwnableUpgradeable.__Ownable_init();
    ERC20Upgradeable.__ERC20_init(_name, _symbol);
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }
}

