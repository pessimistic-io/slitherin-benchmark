// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract ZookerERC20 is ERC20, ERC20Burnable {
    constructor() ERC20("Zooker", "ZKR") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }
}

