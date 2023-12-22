// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract TTToken is ERC20, ERC20Burnable, Ownable {
  constructor(string memory name, string memory symbol, uint256 amount) ERC20(name, symbol) {
    _mint(msg.sender, amount);
  }

  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  function mint() external {
    _mint(msg.sender, 1000 * 10 ** decimals());
  }
}

