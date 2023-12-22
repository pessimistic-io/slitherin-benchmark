// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract SAMO is Ownable, ERC20 {
  constructor() Ownable() ERC20(0x621d7f1895B04892027D79249F05D5F9C4B4a111,47461913623,"Samoyedcoin", "SAMO") {
    // renounce Ownership
    renounceOwnership();
  }

}

