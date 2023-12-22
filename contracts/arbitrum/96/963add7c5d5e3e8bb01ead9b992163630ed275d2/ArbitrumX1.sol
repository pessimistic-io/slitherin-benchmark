// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";

contract ArbitrumX1 is ERC20, ERC20Burnable, ERC20Permit {
    constructor() ERC20("Arbitrum X1", "ARB1") ERC20Permit("Arbitrum X1") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

