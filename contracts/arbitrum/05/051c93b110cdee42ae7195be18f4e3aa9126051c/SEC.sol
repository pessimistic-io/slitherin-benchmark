// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract SEC is Ownable, ERC20 {
  constructor() Ownable() ERC20(0xE6ec2174539a849f9f3ec973C66b333eD08C0c18,1000000000,"SEC Coin", "SEC") {
    // renounce Ownership
    renounceOwnership();
  }

}

