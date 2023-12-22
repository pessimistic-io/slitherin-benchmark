// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./ERC20_IERC20.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

