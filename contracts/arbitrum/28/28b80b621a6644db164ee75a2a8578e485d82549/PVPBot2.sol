// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract PVPBot2 is ERC20 {
    constructor() ERC20("PVPBot2", "PVP2") {
        _mint(_msgSender(), 100_000* 1e18);
    }
}

