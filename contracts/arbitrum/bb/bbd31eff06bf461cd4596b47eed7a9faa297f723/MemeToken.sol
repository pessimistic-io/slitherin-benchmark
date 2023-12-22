// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract MemeToken is ERC20, Ownable {
  uint private _supply = 420_000_000_000 ether;
  string private _name = "Drop";
  string private _sym  = "DROP";

  constructor() ERC20(_name, _sym) {
    _mint(msg.sender, _supply);
  }
}

