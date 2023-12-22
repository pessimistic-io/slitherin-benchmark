// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./draft-ERC20Permit.sol";

contract TestToken is ERC20, ERC20Burnable, ERC20Permit {
    constructor() ERC20("Test Token", "USDC") ERC20Permit("Test Token") {
        _mint(msg.sender, 100000000 * 10 ** decimals());
    }
}

