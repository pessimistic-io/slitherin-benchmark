// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IStrategy {

    function enter(uint256 _amountin, uint256 _pid) external;

    function withdrawall(uint256 _pid) external;
}
