// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract DONS is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("The DONS", "DONS") {
    address wallet = 0x966Cf5cd0624f1EfCf21B0abc231A5CcC802B861;

    _mint(wallet, 10000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

