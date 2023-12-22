// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract FundsHolder {
    using SafeERC20 for IERC20;

    address immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function transferTokenTo(
        address token,
        uint256 amount,
        address to
    ) external {
        require(msg.sender == owner);
        IERC20(token).safeTransfer(to, amount);
    }
}

