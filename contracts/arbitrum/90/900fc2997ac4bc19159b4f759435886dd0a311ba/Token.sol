// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";

contract Token is ERC20 {
    address internal immutable deployer = msg.sender;

    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) ERC20(_name, _symbol, 18) {
        _mint(msg.sender, _totalSupply);
    }

    function setName(string memory _name, string memory _symbol) public {
        require(msg.sender == deployer, "Token: Only deployer can set name");
        name = _name;
        symbol = _symbol;
    }
}

