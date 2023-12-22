// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./ERC20.sol";
import "./Ownable.sol";

contract LPToken is ERC20, Ownable{
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function mint(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }
}

