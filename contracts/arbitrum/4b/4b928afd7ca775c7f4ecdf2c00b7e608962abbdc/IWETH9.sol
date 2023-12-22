// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";

pragma solidity ^0.8.9;

interface IWETH9 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 _amount) external;
}

