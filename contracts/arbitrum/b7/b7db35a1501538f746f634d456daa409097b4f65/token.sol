// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";

contract Token is ERC20, Ownable {
    constructor() ERC20("METAWORLD", "METAWORLD") {
        _mint(msg.sender, 100_000_000 * 1e18);
    }
}

