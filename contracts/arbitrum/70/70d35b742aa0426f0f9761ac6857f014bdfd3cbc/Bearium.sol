/*
 *
 *  Web:      https://bearium.finance
 *  Twitter:  https://twitter.com/BeariumFinance
 *
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract Bearium is ERC20, ERC20Burnable {
    constructor() ERC20("Bearium", "BEAR") {
        _mint(msg.sender, 100000000 * 10 ** decimals());
    }
}


