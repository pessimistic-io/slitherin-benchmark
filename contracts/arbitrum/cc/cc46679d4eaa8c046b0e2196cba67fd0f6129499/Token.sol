// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract T1000 is ERC20, Ownable {
  constructor() ERC20("T1001", "T1001") {
    _mint(msg.sender, 1000000 * 10 ** decimals());
  }
}
