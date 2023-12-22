// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC20PresetFixedSupply.sol";

contract FAC is ERC20PresetFixedSupply{

    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20PresetFixedSupply(name, symbol, initialSupply, msg.sender){}
}

