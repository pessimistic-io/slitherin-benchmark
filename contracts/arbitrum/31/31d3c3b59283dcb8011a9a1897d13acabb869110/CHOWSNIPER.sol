// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";

contract CHOWSNIPER is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    constructor() ERC20("CHOWSNIPER", "CHSNP") ERC20Permit("CHOWSNIPER") {
        _mint(msg.sender, 1000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}


