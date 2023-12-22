// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";

contract PVPBot3 is ERC20 {
    constructor() ERC20("PVPBot3", "PVP3") {
        _mint(_msgSender(), 100_000* 1e18);
    }
}

