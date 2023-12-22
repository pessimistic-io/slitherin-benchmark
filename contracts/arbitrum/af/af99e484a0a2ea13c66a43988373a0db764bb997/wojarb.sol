/*
Wojarb is a 100% meme community-owned token.

0% tax
Liquidity Locked
Contract renounced

twitter: @wojarbcoin
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract Wojarb is ERC20, Ownable {
  constructor() ERC20("Wojarb", "WOJARB") {
    _mint(msg.sender, 1000000 * 10 ** decimals());
  }
}

