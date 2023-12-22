// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract PepeDex is ERC20, Ownable {
  uint private _supply = 69_420_000_000 ether;
  string private _name = "Pepe Dex";
  string private _sym  = "PEPEX";

  constructor() ERC20(_name, _sym) {
    _mint(msg.sender, _supply);
  }
}

