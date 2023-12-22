// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract AGC is ERC20 {
    constructor() ERC20("Arbitrum GameFi Carnival", "AGC") {
        _mint(_msgSender(), 1e8 * 10 ** decimals());
    }
}

