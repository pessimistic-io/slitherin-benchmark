// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";

contract Shrimp is ERC20 {
    constructor() ERC20("Shrimp", "SHRIMP") {
        _mint(msg.sender, 1000000000 ether);
    }
}

