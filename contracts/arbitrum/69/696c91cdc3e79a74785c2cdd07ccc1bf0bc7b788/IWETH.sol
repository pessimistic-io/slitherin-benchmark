// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.15;

import "./interfaces_IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

