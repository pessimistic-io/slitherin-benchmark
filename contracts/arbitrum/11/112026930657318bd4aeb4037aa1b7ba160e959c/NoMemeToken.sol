// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";

contract NoMemeToken is ERC20 {
    constructor() ERC20("NoMeme", "NOMEME") {
        _mint(msg.sender, 650_000_000 ether);
    }
}

