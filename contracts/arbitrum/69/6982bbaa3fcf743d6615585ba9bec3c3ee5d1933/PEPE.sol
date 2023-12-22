// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract PEPE is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("Pepe", "PEPE") {
    address wallet = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;

    _mint(wallet, 420690000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

