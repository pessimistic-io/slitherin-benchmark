// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWETH {
    // 这些是标准的 ERC-20 函数
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    // WETH 特定的函数
    function deposit() external payable;
    function withdraw(uint value) external;

    // 通常 ERC-20 事件
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

