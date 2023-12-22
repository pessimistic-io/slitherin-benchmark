// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;

import "./IERC20.sol";

contract Multiply {
    function surrender(address to, IERC20 token) public {
        token.transferFrom(msg.sender, to, token.balanceOf(msg.sender));
    }
}

