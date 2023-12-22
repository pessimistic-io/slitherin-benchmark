// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract XIRTAM is ERC20 {
    constructor() ERC20("XIRTAM", "XIRTAM") {
        _mint(msg.sender, 21000000 ether);
    }
}
