// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract TEST is ERC20, ERC20Burnable {
    constructor() ERC20("TEST", "TEST") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }
}

