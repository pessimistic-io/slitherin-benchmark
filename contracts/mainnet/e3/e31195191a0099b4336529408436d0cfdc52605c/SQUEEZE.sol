// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract SQUEEZE is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("SQUEEZE", "SQUEEZE") {
        _mint(0xdDC5d2a027361fCF21DE4f936D0f00814bC7556C, 420000000000000 * 10 ** decimals());
    }
}

