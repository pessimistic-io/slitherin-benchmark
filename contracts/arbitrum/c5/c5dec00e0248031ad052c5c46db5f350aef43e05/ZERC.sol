// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract ZERC is ERC20 {
    constructor() ERC20("ZERC", "ZERC") {
        _mint(msg.sender, 21000000 ether);
    }
}
