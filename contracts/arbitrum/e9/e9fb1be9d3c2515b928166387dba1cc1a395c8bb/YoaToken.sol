// SPDX-License-Identifier: Unlicensed

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.19;

import "./ERC20.sol";

contract YoaToken is ERC20 {
    constructor() ERC20("Yoa", "YOA") {
        _mint(msg.sender, 31000000 * 10 ** decimals());
    }
}
