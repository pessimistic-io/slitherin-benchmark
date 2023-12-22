// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract MEMEME is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("MEMEME", "MEMEME") {
    address wallet = 0x472ac74b4c82FccEE01519D444c9D400b5F8a04e;

    _mint(wallet, 69420000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

