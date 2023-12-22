// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract Test is ERC20 {

    uint256 public MAX_SUPPLY = 10000 ether;

    constructor() ERC20("test", "test"){
        _mint(msg.sender, MAX_SUPPLY);
    }

}

