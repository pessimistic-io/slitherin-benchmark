// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract AIFLOKI is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("AIFloki", "AIFLOKI") {
    address wallet = 0x69F74D7DD69251255853509A5F3cB53FCB20F716;

    _mint(wallet, 420690000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

