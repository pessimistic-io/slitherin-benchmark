// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWrapped {
    function deposit() external payable;

    function withdraw(uint wad) external;
}

