// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20.sol";

contract People is ERC20 {
    constructor() ERC20("People", "PEOPLE") {
        _mint(msg.sender, 10_000_000_000 ether);
    }
}

