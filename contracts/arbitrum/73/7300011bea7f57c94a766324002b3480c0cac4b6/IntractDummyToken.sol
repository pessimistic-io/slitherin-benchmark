// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract DummyToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = type(uint256).max;

    constructor() ERC20("Intract Dummy Token", "IDT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 1;
    }
}
