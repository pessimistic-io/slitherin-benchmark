// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ERC20.sol";


contract Zoo is ERC20 {
    constructor(uint amount) ERC20("ZooDAO", "ZOO") {
        _mint(msg.sender, amount);
    }
}

