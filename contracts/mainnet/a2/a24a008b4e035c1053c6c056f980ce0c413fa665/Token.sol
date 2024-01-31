//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract SUGONDESE is ERC20 {
    uint constant _initial_supply = 100000000000 * (10**18);
    constructor() ERC20("SUGONDESE", "SUGON") {
        _mint(msg.sender, _initial_supply);
    }
}
