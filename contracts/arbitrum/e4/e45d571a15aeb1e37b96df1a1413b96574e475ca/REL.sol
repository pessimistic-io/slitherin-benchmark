// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract REL is Ownable, ERC20 {
  constructor() Ownable() ERC20(0x592bA1CC7f1c8685a0CCafad94Ad95F8Af4651bc,1000000000,"Relation Token", "REL") {
    // renounce Ownership
    renounceOwnership();
  }

}

