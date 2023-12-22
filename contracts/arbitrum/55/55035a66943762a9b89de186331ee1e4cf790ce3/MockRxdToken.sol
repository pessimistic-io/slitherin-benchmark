// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract MockRxdToken is ERC20 {
    constructor() ERC20("MOCK-RXD", "MRXD") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

