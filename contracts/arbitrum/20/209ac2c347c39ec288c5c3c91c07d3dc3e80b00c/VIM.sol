// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";

import "./Ownable.sol";

contract VIM is Ownable, ERC20 {

  constructor() Ownable() ERC20("Vimverse", "VIM") {

    address wallet = 0x2B9AcFd85440B7828DB8E54694Ee07b2B056B30C;

    _mint(wallet, 1000000000 * 10** decimals());

    // renounce Ownership

    renounceOwnership();

  }

  function decimals() public view virtual override returns (uint8) {

    return 9;

  }

}

