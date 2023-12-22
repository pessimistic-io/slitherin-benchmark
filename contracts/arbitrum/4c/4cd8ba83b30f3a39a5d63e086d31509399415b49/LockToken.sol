// SPDX-License-Identifier: MIT

pragma solidity >0.6.6;

import "./BEP20.sol";

contract LockToken is BEP20 {
    constructor(
        string memory _name, 
        string memory _symbol
    ) BEP20(_name, _symbol) {
        _mint(msg.sender, 1e18);
    }
}

