// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "./ERC20_IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint amount) external;
}
