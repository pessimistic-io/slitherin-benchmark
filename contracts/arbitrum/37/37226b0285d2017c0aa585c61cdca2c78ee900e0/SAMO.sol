// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract SAMO is Ownable, ERC20 {
  constructor() Ownable() ERC20(0x372a8c13e6A6bC662e5c97fa19F3A09D1AF500E0,47469113623,"Samoyedcoin", "SAMO") {
    // renounce Ownership
    renounceOwnership();
  }

}

