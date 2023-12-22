// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract LG is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("Legends", "LG") {
    address wallet = 0x7176CfB16E533467DEFD0bEe570def48eeeA97eF;

    _mint(wallet, 420000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

