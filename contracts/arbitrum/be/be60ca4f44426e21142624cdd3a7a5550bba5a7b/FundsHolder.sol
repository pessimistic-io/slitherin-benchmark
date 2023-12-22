// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract FundsHolder {
    using SafeERC20 for IERC20;

    address immutable operator;

    constructor() {
        operator = msg.sender;
    }

    function transfer(address token, uint256 amount, address to) external {
        require(msg.sender == operator);
        IERC20(token).safeTransfer(to, amount);
    }
}

