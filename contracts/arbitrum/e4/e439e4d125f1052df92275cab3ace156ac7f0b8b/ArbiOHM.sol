// SPDX-License-Identifier: MIT

/*

https://t.me/ArbiOHM

Stealth OHM Fork on Arbitrum

*/

pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./Ownable.sol";

contract ArbiOHM is ERC20, Ownable {

    constructor() ERC20("ArbiOHM", "AOHM") {
        _mint(msg.sender, 1 * 1e4 * 1e18);
    }

    receive() external payable {} 

}

