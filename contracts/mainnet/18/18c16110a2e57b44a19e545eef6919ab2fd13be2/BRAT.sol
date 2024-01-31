// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract BRAT is ERC20, ERC20Burnable {
    constructor() ERC20("BRAT", "BRAT")
    {
        _mint(msg.sender, 420690000000000 * 10 ** decimals());
    }
}
