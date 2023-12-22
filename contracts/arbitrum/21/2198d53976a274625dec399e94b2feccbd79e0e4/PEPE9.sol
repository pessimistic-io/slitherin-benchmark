// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract PEPE9 is ERC20 {

    uint256 public MAX_SUPPLY = 990_000_000_000 ether;

    constructor() ERC20("PEPE9.9", "PEPE9.9"){
        _mint(msg.sender, MAX_SUPPLY);
    }

}

