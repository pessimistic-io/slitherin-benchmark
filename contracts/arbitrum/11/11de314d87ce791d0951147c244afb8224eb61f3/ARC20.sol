// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC20.sol";

contract ARC20 is ERC20 {
    uint constant UINT = 12 * 10 ** 23;

    constructor() ERC20("arc", "arc") {
        _mint(msg.sender, 10500 * UINT);
    }
}

