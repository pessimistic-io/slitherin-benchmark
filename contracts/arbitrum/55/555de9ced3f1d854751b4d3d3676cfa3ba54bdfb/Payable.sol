// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Sale} from "./Sale.sol";
import {ERC20} from "./ERC20.sol";

abstract contract Payable is Sale {
    event Rescue(address indexed token, address indexed to, uint256 amount);
    event Paied(address indexed payeer, uint256 amount);

    function _takeMoney(uint256 amount) internal virtual;

    function rescueTokens(
        ERC20 token,
        address to,
        uint256 amount
    ) external requiresAuth {
        token.transfer(to, amount);
        emit Rescue(address(token), to, amount);
    }

    function rescueTokens(address payable to, uint256 amount)
        external
        requiresAuth
    {
        to.transfer(amount);
        emit Rescue(address(0), to, amount);
    }
}

