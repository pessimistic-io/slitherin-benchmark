// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract FundsHolder is Ownable {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) {}

    function transferTokenTo(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
}

