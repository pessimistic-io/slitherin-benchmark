// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract WISTA is Ownable, ERC20 {
  constructor() Ownable() ERC20(0x136f63CB8817D397493a617f3FA5BE81917e2C9c,4200000000,"Wistaverse", "WISTA") {
    // renounce Ownership
    renounceOwnership();
  }

}

