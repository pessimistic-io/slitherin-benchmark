// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ERC20 } from "./ERC20.sol";

/// @title GreenChain Token
/// @notice Limited issue GreenChain Token
contract GreenChain is ERC20 {
  constructor(uint _initialSupply) ERC20("GreenChain", "GREEN", 18) {
    _mint(msg.sender, _initialSupply); // note msg.sender will not work for create2 deployment
  }
}

