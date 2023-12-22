/*
 *
 *  Twitter:  https://twitter.com/PepeTheArb
 *  App:      https://www.pepearb.gay
 *  Discord:  https://discord.io/PepeTheArb
 *
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract PEPEARB is ERC20, ERC20Burnable {
    constructor() ERC20("Pepe Arbitrum", "PEPEARB") {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }
}
