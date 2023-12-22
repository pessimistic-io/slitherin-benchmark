// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract SiliconValleyBank is ERC20 {
    constructor(uint256 initialSupply) ERC20("Silicon Valley Bank", "SVB") {
        _mint(msg.sender, initialSupply);
    }
}
