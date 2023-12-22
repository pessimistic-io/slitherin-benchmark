//SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IWETH {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function deposit() external payable;

    function transfer(address to, uint value) external returns (bool);

    function withdraw(uint) external;

    function approve(address spender, uint256 amount) external returns (bool);
}

