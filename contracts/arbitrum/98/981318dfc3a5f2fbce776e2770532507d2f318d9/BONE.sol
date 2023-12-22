// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract BONE is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("BONE SHIBASWAP", "BONE") {
    address wallet = 0xc7D0445ac2947760b3dD388B8586Adf079972Bf3;

    _mint(wallet, 2300030220 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

