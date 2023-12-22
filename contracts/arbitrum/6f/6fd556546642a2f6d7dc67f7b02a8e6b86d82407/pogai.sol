// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract pogai is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("poor guy", "pogai") {
    address wallet = 0x75C6E6038e7826747b25906AE89D7C5BE54F67C3;

    _mint(wallet, 100000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

