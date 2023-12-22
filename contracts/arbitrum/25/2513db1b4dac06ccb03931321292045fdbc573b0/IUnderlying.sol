// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

interface underlying {
    function approve(address spender, uint value) external returns (bool);
    function mint(address, uint) external;
    function totalSupply() external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function transfer(address, uint) external returns (bool);
    function MAX_SUPPLY() external view returns (uint);
}

