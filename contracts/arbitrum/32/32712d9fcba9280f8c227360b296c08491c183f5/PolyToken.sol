// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./draft-ERC20Permit.sol";

contract PolyToken is ERC20Permit {
    constructor() ERC20("TestToken", "Test") ERC20Permit("TestToken") {
    // constructor() ERC20("Monopoly Poly", "POLY") ERC20Permit("Monopoly Poly") {
        _mint(msg.sender, 10000000 * 10 ** decimals());
    }
}

