// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;


interface IERC20{
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns(bool);
}
