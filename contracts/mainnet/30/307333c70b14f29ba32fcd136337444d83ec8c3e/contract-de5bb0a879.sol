// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract Test is ERC20 {
    constructor() ERC20("test", "test") {}
}

