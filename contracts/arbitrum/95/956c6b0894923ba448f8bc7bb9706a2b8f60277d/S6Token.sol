// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "./ERC20.sol";

contract S6Token is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 5_000_000e18;

    constructor() ERC20("S6 Token", "S6T") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

