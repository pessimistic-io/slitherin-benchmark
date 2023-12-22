// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract UltraInstinctV4 is ERC20 {
    constructor() ERC20("UltraInstinctV4", "UIV4") {
        _mint(_msgSender(), 100_000* 1e18);
    }
}

