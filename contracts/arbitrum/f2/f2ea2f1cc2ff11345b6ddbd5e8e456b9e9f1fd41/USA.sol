// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";

contract USAMeme is ERC20 {
    constructor() ERC20("USA Meme", "USA") {
        _mint(msg.sender, 420690000000000 * 10 ** decimals());
    }
}
