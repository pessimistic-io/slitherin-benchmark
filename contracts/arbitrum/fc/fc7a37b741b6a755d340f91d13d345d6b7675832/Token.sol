// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract Token is ERC20, ERC20Burnable {
    constructor() ERC20("Weed PEPE", "WEPE") {
        _mint(msg.sender, 100 ** 9 * 10 ** 9); //1 billion total supply
    }
}

