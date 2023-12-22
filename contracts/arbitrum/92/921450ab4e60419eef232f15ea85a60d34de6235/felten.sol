/*
Felten is a 100% community-owned token in honour of Ed Felten, co-founder of Arbitrum.

0% tax
Liquidity Locked
Contract renounced

At 100k marketcap we will forever burn the LP and the top 50% of holders will be airdropped a gift in their wallets for having trusted and believed in Felten.

No official telegram, no website, no dev, only twitter: @feltentoken
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract Felten is ERC20, Ownable {
  constructor() ERC20("Felten", "FELTEN") {
    _mint(msg.sender, 1000000 * 10**decimals());
  }
}

