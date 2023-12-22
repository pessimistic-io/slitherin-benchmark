// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import "./ERC20.sol";
import "./Ownable.sol";

contract Blocso is ERC20, Ownable {
    constructor() Ownable(msg.sender) ERC20("Blocso", "BLCO") {
        _mint(owner(), 10000000000 * 10 ** decimals());
    }
}

