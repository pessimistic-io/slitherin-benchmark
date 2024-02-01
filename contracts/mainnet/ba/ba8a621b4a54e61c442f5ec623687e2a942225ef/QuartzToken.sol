// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract QuartzToken is ERC20("Sandclock", "QUARTZ") {
    constructor() {
        _mint(msg.sender, 1e8 ether);
    }
}

