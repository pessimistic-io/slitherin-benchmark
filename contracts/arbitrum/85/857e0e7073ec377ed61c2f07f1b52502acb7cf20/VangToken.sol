// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract VangToken is ERC20("Cau Vang", "VANG", 18) {
    uint256 public constant MAX_SUPPLY = 999_999_999_999 ether;

    constructor() {
        _mint(msg.sender, MAX_SUPPLY);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}

