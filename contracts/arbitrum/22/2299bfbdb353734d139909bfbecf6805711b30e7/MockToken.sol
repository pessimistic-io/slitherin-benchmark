// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ERC20.sol";

contract MockToken is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        _mint(msg.sender, 50000 ether);
    }
}

