// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.9;


/**
 * https://slasha.vitalik.eth.limo/
 */

import "./ERC20.sol";
import "./Ownable.sol";


contract Slasha is ERC20, Ownable {

  constructor() ERC20("SLASHA", "SLASHA") {
    _mint(msg.sender, 1000000000 * 10 ** decimals());
  }

}
