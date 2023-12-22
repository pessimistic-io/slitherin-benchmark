// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";

interface IwETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

