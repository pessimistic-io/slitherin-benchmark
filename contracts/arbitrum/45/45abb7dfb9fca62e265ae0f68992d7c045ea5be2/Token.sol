// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("ATLAS", "ATLAS") {
        _mint(msg.sender, 100_000_000 * 10**18);
    }
}

