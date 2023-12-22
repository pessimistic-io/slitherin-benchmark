// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

contract CrazyToken is ERC20, Ownable {
    constructor(uint256 amount) ERC20("Crazy Token", "CZY") {
         _mint(msg.sender, amount);
    }

}
