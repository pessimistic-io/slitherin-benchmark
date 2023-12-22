// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20.sol";

contract PeopleX is ERC20 {
    constructor() ERC20("PeopleX", "PEOPLEX") {
        _mint(msg.sender, 10_000_000_000 ether);
    }
}

