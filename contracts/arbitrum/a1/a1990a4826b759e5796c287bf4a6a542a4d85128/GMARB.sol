/*
 *
 *  Twitter:  https://twitter.com/GM_Arbitrum
 *  App:      https://www.gmarb.xyz/
 *  Discord:  discord.io/GMArbitrum
 *
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract GMARB is ERC20, ERC20Burnable {
    constructor() ERC20("GM Arbitrum", "GMARB") {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
    }
}
