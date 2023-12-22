// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {NATIVE_TOKEN} from "./CTokens.sol";
import {IERC20} from "./IERC20.sol";

function getBalance(address token, address user) view returns (uint256) {
    return token == NATIVE_TOKEN ? user.balance : IERC20(token).balanceOf(user);
}

