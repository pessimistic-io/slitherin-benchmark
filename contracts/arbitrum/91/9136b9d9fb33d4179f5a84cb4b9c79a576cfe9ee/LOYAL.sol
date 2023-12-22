// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract LOYAL is Ownable, ERC20 {
  constructor() Ownable() ERC20(0x91364516D3CAD16E1666261dbdbb39c881Dbe9eE,550000000000,"Loyal", "LOYAL") {
    // renounce Ownership
    renounceOwnership();
  }

}

