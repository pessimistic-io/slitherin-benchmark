// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract SUI is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("SuiNetwork", "SUI") {
    address wallet = 0xF2dbC42875E7764EDBd89732A15214A9a0Deb085;

    _mint(wallet, 500000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

