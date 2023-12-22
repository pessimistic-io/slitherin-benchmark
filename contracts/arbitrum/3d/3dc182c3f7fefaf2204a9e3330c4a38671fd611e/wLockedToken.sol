//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

interface Parent {
    function onTransfer(address from ,address to, uint amount) external;
}

contract wLockedToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint amount) external onlyOwner {
        _burn(account, amount);
    }

    function manage(address from, address to, uint amount) external onlyOwner {
        _transfer(from, to, amount);
    }

    function transfer(address, uint256) public virtual override returns (bool) {
        return false;
    }
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        return false;
    }

    function _afterTokenTransfer(address from ,address to, uint amount) internal override {
        Parent(owner()).onTransfer(from, to, amount);
    }
}

