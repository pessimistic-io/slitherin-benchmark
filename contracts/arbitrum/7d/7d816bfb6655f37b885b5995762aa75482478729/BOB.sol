// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract BOB is Ownable, ERC20Burnable {
  constructor() Ownable() ERC20("BOB", "BOB") {
    address wallet = 0x37cE3a20578094adE8aEaccD1879a605bdABE7ad;

    _mint(wallet, 690000000000 * 10** decimals());

    // renounce Ownership
    renounceOwnership();
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }
}

