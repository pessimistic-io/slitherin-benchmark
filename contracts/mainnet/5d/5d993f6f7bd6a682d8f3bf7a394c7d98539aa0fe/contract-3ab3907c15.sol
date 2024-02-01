// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract CZ47 is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("CZ47", "CZ47") {
        _mint(msg.sender, 690000000000000 * 10 ** decimals());
    }
}

