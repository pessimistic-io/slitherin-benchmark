// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8;

import "./IERC20.sol";

/// @title WETH9
interface IWETH9 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

