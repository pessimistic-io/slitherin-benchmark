// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract ONLY1TOKEN is ERC20, Ownable {
    constructor() ERC20("ONLY 1 TOKEN", "1T") {
        _mint(msg.sender, 1 * 10 ** decimals());
    }
}

