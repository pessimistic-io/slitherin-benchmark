// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.7;

import "./ERC20.sol";

contract TycheFinanceToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Tyche Finance Token", "TCH") {
        _mint(msg.sender, initialSupply);
    }
}

