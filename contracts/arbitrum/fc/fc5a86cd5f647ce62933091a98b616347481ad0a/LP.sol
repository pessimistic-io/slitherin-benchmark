// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";

import "./Ownable.sol";

import "./ERC20Burnable.sol";

contract LP is Ownable, ERC20Burnable {

  constructor() Ownable() ERC20("LiquityProtocol", "LP") {

    address wallet = 0xC32eB36f886F638fffD836DF44C124074cFe3584;

    _mint(wallet, 1000000000 * 10** decimals());

    // renounce Ownership

    renounceOwnership();

  }

  function decimals() public view virtual override returns (uint8) {

    return 9;

  }

}

