// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract NAMToken is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("Namjai", "NAM") {
        _mint(msg.sender, 16);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

