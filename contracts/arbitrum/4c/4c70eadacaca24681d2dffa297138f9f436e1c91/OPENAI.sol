// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract OPENAI is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("OPEN AI", "OPENAI") {
    address wallet = 0x9C0aAcB8Ea4DE09F6AB66c21Dca0C7d710646547;

    _mint(wallet, 10000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

