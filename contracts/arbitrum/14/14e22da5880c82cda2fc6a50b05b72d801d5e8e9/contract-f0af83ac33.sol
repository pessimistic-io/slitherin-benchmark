// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract SimpleToken is ERC20 {
    constructor() ERC20("SIMPLE-ARBI", "SIMPLE-ARBI") {
        _mint(msg.sender, 1 * 10 ** decimals());
    }
}

