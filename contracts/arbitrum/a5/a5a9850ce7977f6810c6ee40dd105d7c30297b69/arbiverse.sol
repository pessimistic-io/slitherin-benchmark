//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract Arbiverse is ERC20 {
    uint constant _initial_supply = 20000000 * (10**18);
    constructor() ERC20("Arbiverse", "ARBV") {
        _mint(msg.sender, _initial_supply);
    }
}
