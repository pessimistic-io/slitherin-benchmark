// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract MX is ERC20 {

    uint256 public immutable MAX = 20000000000 ether;

    constructor() ERC20("MX", "MX") {
        _mint(msg.sender, MAX);
    }

}
