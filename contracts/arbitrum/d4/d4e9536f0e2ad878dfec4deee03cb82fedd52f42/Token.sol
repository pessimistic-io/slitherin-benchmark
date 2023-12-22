// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract FroggilyToken is ERC20 {
    constructor() ERC20("Froggily", "FROY") {
        _mint(msg.sender, 100_000_000_000 * 10 ** decimals());
    }
}

