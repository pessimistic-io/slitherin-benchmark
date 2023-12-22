// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.2;

interface IwETH {
    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function balanceOf(address owner) external view returns (uint256);
}

