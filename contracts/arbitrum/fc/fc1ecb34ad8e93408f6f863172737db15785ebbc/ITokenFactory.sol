// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

interface ITokenFactory {
    function manager() external view returns (address);
    function owner() external view returns (address);
    function transferWhitelist(address) external view returns (bool);
    function allowanceWhitelist(address) external view returns (bool);
}

