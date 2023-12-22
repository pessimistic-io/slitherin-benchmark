//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

interface Parent {
    function onTransfer(address from ,address to, uint amount) external;
}

contract wToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint amount) external onlyOwner {
        _burn(account, amount);
    }

    function _transfer(address from ,address to, uint amount) internal override {
        Parent(owner()).onTransfer(from, to, amount);
    }
}
