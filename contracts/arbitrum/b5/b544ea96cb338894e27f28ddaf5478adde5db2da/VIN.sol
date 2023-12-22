// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract VIN is ERC20WithSupply {
    string public constant symbol = "VIN";
    string public constant name = "VIN";
    uint8 public constant decimals = 18;

    constructor() {
        _mint(msg.sender, 1e7 ether);
    }
}

