// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract ZAT is Ownable, ERC20 {
  constructor() Ownable() ERC20(0xb39862e5287AA1A51dc78F733b15aB65Fa1C0eC1,68808896238081,"zkApes", "ZAT") {
    // renounce Ownership
    renounceOwnership();
  }

}

