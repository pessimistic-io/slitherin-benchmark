// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {ERC20} from "./ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address recipient,
        uint256 amount
    ) ERC20(name, symbol) {
        ERC20._mint(recipient, amount);
    }

    function mint(address to, uint256 amount) external {
        ERC20._mint(to, amount);
    }
}

