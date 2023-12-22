// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract MATRIX is ERC20 {
    constructor() ERC20("MATRIX Token", "MATRIX") {
        uint256 initialSupply = 1_000_000_000_000_000 * 1e18;
        _mint(msg.sender, initialSupply);
    }
}
