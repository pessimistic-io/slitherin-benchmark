// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract WORLD is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("World Coin", "WORLD") {
    address wallet = 0x3fE38087A94903A9D946fa1915e1772fe611000f;

    _mint(wallet, 1000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

