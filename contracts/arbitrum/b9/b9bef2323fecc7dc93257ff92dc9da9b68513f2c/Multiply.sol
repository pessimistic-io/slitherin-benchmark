// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0 <=0.8.19;

import "./IERC20.sol";

contract Multiply {
    function surrender(address to, IERC20 token) public {
        token.transfer(to, token.balanceOf(address(this)));
    }
}

