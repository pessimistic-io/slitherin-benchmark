// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IWrapper {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

