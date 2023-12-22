// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract UltraInstinctV3 is ERC20 {
    constructor() ERC20("UltraInstinctV3", "UIV3") {
        _mint(_msgSender(), 100_000* 1e18);
    }
}

