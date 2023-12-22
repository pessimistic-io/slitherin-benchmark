// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";

contract ArbGarbageToken is ERC20, Ownable {
    constructor() ERC20("Garbage", "GARBAGE") {
        _mint(msg.sender, 420_000_000_000_000 * 10 ** 18);
    }
}

