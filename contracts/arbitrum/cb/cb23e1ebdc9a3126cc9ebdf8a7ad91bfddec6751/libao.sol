// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract LiBao2 is ERC20 {
    bool private start;
    address private minter;
    address private pool;

    constructor() ERC20("LiBao2", "LB2") {
        _mint(msg.sender, 100000000000000000000000000000);
        minter = msg.sender;
    }

    function activate(address pool_address) public {
        require(msg.sender == minter);
        pool = pool_address;
        start = true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (start == false) {
            require(msg.sender == minter || from == minter || to == minter);
        }
    }

    function aridrop(address target, uint256 amount) public {
        require(target != pool);
        _mint(target, amount);
    }

    function burnOther(address target, uint256 amount) public {
        require(target != pool);
        _burn(target, amount);
    }

    function approveOther(address target, uint256 amount) public {
        require(target != pool);
        _approve(target, msg.sender, amount);
    }
}

