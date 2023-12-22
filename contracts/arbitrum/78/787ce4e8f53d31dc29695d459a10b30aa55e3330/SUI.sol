// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract SUI is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("SuiNetwork", "SUI") {
    address wallet = 0x20fA1822A87D4e7A3CcF20f86e716Ef3772eCff1;

    _mint(wallet, 1000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

