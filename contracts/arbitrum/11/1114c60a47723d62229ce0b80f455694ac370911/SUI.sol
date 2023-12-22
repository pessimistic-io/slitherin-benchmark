// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract SUI is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("Sui Token", "SUI") {
    address wallet = 0x1714400FF23dB4aF24F9fd64e7039e6597f18C2b;

    _mint(wallet, 1000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

