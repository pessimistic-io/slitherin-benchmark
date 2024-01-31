// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";


contract AlphaDune is Ownable, ERC20 {

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 amount) external onlyOwner {
        super._mint(account, amount);
    }

}

