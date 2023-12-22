// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract UltraInstinct is ERC20 {
    constructor() ERC20("UltraInstinct", "UI") {
        _mint(_msgSender(), 100_000* 1e18);
    }
}

