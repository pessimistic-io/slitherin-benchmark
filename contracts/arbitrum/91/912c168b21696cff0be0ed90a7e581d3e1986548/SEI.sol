// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "./ERC20.sol";

import "./Ownable.sol";

import "./ERC20Burnable.sol";

contract SEI is Ownable, ERC20Burnable {

  constructor() Ownable() ERC20("Sei Network", "SEI") {

    address wallet = 0x67a24CE4321aB3aF51c2D0a4801c3E111D88C9d9;

    _mint(wallet, 1000000000 * 10** decimals());

    // renounce Ownership

    renounceOwnership();

  }

  function decimals() public view virtual override returns (uint8) {

    return 9;

  }

}

