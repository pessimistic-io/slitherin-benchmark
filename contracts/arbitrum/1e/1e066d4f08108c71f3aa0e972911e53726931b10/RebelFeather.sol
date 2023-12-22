// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract RebelFeather is ERC20 {
    constructor() ERC20("Rebel Feather", "reFeather") {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }
}
