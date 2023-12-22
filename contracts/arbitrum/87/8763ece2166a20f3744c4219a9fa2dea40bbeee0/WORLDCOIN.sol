// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract WORLDCOIN is Ownable, ERC20Burnable {
  function decimals() public view virtual override returns (uint8) {
    return 9;
  }

  constructor() Ownable() ERC20("WORLD COIN", "WORLDCOIN") {
    _mint(0xD763167b2FFFF1f5FE998B1a82dc0f6C8Cf4E152, 1000000000 * 10** decimals());
    // renounce Ownership
    renounceOwnership();
  }

}

