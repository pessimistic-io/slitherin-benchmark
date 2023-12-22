// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ERC20} from "./ERC20.sol";

contract TestERC20 is ERC20 {

    constructor(uint256 initSupply, string memory name_, string memory symbol_) ERC20(name_, symbol_){
        _mint(msg.sender, initSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
