// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC20.sol";

contract Jarvis is ERC20 {
    constructor() ERC20("Jarvis AI", "JAI") {
        _mint(msg.sender, 100000000 * 10 ** decimals());
    }
}

