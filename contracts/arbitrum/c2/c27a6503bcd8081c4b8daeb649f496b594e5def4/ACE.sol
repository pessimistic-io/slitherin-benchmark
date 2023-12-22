// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";

import "./Ownable.sol";

import "./ERC20Burnable.sol";

contract ACE is Ownable, ERC20Burnable {

  constructor() Ownable() ERC20("ACEToken", "ACE") {

    address wallet = 0x2bA7EDC27c15b3baE40866005012f529F254e3fC;

    _mint(wallet, 147000000 * 10** decimals());

    // renounce Ownership

    renounceOwnership();

  }

  function decimals() public view virtual override returns (uint8) {

    return 9;

  }

}

