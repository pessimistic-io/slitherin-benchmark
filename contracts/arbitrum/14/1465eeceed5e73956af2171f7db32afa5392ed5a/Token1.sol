// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract Token1 is ERC20 {
    constructor() ERC20('Token1', 'TK1'){
        _mint(msg.sender, 10000000 ether);
    }
}

