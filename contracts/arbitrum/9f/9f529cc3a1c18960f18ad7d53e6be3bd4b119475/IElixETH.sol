// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "./ERC20_IERC20.sol";

interface IElixETH is IERC20 {
    function deposit() external payable;

    function depositTo(address to) external payable;

    function withdraw(uint256 amount) external;

    function withdrawTo(address to, uint256 amount) external;
}

