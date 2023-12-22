// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./IERC20.sol";

interface ITestERC20 is IERC20 {
    function mint(uint256 amount, address receiver) external;
}

