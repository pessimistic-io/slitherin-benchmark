// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract SEI is Ownable, ERC20 {
  constructor() Ownable() ERC20(0x71866f0215468D9D458F1a769e5D28f4bd1B7C7b,1000000000,"Sei Labs", "SEI") {
    // renounce Ownership
    renounceOwnership();
  }

}

